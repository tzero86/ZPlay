package io.github.tzero86.zplay

import android.app.Activity
import android.content.Context
import android.os.Build
import android.util.Log
import dalvik.system.DexClassLoader
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.lang.reflect.InvocationHandler
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.zip.ZipFile

class CloudStreamNativeBridge(private val context: Context, private val activity: Activity?) {
    private val TAG = "CloudStreamNative"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var runtimeBridge: Any? = null
    private var bridgeClass: Class<*>? = null
    private var videoStreamJob: Job? = null
    private var lastLoadError: Throwable? = null
    private val activeJobs = java.util.concurrent.ConcurrentHashMap.newKeySet<Job>()
    @Volatile
    private var cachedProviders: List<Map<String, Any?>>? = null

    fun register(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "anymeXBridge").setMethodCallHandler { call, result ->
            when (call.method) {
                "loadAnymeXRuntimeHost" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_ARG", "path is required", null)
                        return@setMethodCallHandler
                    }
                    scope.launch {
                        try {
                            val ok = loadRuntimeHost(path)
                            withContext(Dispatchers.Main) {
                                if (ok) {
                                    result.success(true)
                                } else {
                                    val err = lastLoadError
                                    val msg = err?.message ?: "Failed to load runtime host APK"
                                    val details = if (err != null) Log.getStackTraceString(err) else null
                                    result.error("LOAD_FAILED", msg, details)
                                }
                            }
                        } catch (e: Throwable) {
                            withContext(Dispatchers.Main) {
                                result.error("BRIDGE_ERROR", e.message, Log.getStackTraceString(e))
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "cloudstreamExtensionBridge").setMethodCallHandler { call, result ->
            handleCloudStream(call, result)
        }

        EventChannel(messenger, "cloudstreamExtensionBridge/videoStream").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val args = arguments as? Map<*, *> ?: return
                val apiName = args["apiName"] as? String ?: return
                val url = args["url"] as? String ?: return
                val params = (args["parameters"] as? Map<String, Any?>)?.toMutableMap() ?: mutableMapOf()
                handleVideoStream(cleanApiName(apiName), url, params, events)
            }

            override fun onCancel(arguments: Any?) {
                videoStreamJob?.cancel()
                videoStreamJob = null
            }
        })
    }

    private fun loadRuntimeHost(apkPath: String): Boolean {
        lastLoadError = null
        return try {
            val originalApk = File(apkPath)
            if (!originalApk.exists()) {
                val err = IllegalStateException("APK does not exist at: $apkPath")
                lastLoadError = err
                Log.e(TAG, err.message, err)
                return false
            }

            val cacheApkName = "zplay_cs_runtime.apk"
            val cacheApk = File(context.filesDir, cacheApkName)

            if (!cacheApk.exists() || cacheApk.length() != originalApk.length()) {
                if (cacheApk.exists()) {
                    cacheApk.setWritable(true)
                }
                originalApk.inputStream().use { input ->
                    FileOutputStream(cacheApk).use { output ->
                        input.copyTo(output)
                    }
                }
            }

            // Android 14+ (API 34) strictly requires dynamically loaded DEX/APK files to be marked READ-ONLY!
            // If canWrite() is true, ART throws: java.lang.SecurityException: Writable dex file is not allowed.
            cacheApk.setReadOnly()
            try { originalApk.setReadOnly() } catch (_: Throwable) {}

            val optimizedDir = File(context.codeCacheDir, "cs_dex_${System.currentTimeMillis()}").apply { mkdirs() }
            val libsDir = File(context.filesDir, "cs_native_libs").apply { mkdirs() }

            // Extract native shared libraries (.so) matching the device's ABI from the runtime APK into libsDir
            try {
                extractNativeLibraries(cacheApk, libsDir)
            } catch (e: Throwable) {
                Log.w(TAG, "Warning extracting native libraries: ${e.message}")
            }

            val loader = object : DexClassLoader(
                cacheApk.absolutePath,
                optimizedDir.absolutePath,
                libsDir.absolutePath,
                context.classLoader
            ) {
                override fun findClass(name: String?): Class<*> {
                    if (name == "com.lagradost.cloudstream3.utils.StringUtils") {
                        try {
                            return com.lagradost.cloudstream3.utils.StringUtils::class.java
                        } catch (_: Throwable) {}
                    }
                    return super.findClass(name)
                }

                override fun loadClass(name: String?, resolve: Boolean): Class<*> {
                    if (name == "com.lagradost.cloudstream3.utils.StringUtils") {
                        try {
                            return com.lagradost.cloudstream3.utils.StringUtils::class.java
                        } catch (_: Throwable) {}
                    }
                    return super.loadClass(name, resolve)
                }
            }

            bridgeClass = loader.loadClass("com.anymex.runtimehost.RuntimeBridge")
            runtimeBridge = bridgeClass!!.getField("INSTANCE").get(null)

            // Try 1-arg initialize(context) first; fallback to initialize(context, emptyMap())
            val init1 = bridgeClass!!.methods.firstOrNull { it.name == "initialize" && it.parameterTypes.size == 1 }
            if (init1 != null) {
                init1.invoke(runtimeBridge, context)
            } else {
                call("initialize", context, emptyMap<String, Any?>())
            }

            Log.i(TAG, "CloudStream Android Runtime Host loaded successfully")
            true
        } catch (e: Throwable) {
            lastLoadError = e
            Log.e(TAG, "Failed to load Runtime Host APK: ${e.message}", e)
            false
        }
    }

    private fun extractNativeLibraries(apkFile: File, targetDir: File) {
        val supportedAbis = Build.SUPPORTED_ABIS
        ZipFile(apkFile).use { zip ->
            var matchedAbi: String? = null
            for (abi in supportedAbis) {
                val testEntry = zip.getEntry("lib/$abi/libquickjs.so") ?: zip.getEntry("lib/$abi/libzstd-kmp.so")
                if (testEntry != null) {
                    matchedAbi = abi
                    break
                }
            }
            if (matchedAbi == null && supportedAbis.isNotEmpty()) {
                matchedAbi = supportedAbis[0]
            }
            if (matchedAbi != null) {
                val prefix = "lib/$matchedAbi/"
                val entries = zip.entries()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    if (entry.name.startsWith(prefix) && !entry.isDirectory) {
                        val libName = entry.name.substring(prefix.length)
                        val root = targetDir.canonicalFile
                        val outFile = File(root, libName).canonicalFile
                        if (!outFile.path.startsWith(root.path + File.separator)) {
                            Log.w(TAG, "Skipping native library outside target: ${entry.name}")
                            continue
                        }
                        if (!outFile.exists() || outFile.length() != entry.size) {
                            if (outFile.exists()) outFile.setWritable(true)
                            zip.getInputStream(entry).use { input ->
                                FileOutputStream(outFile).use { output ->
                                    input.copyTo(output)
                                }
                            }
                            outFile.setReadable(true, false)
                            outFile.setExecutable(true, false)
                        }
                    }
                }
            }
        }
    }

    private fun handleCloudStream(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancelOngoingRequests") {
            Log.d(TAG, "Cancelling all ongoing CloudStream requests (${activeJobs.size} active jobs)")
            videoStreamJob?.cancel()
            videoStreamJob = null
            val jobs = activeJobs.toList()
            activeJobs.clear()
            for (j in jobs) {
                j.cancel()
            }
            result.success(true)
            return
        }

        val job = scope.launch {
            try {
                val res: Any? = when (call.method) {
                    "initialize" -> {
                        val init1 = bridgeClass?.methods?.firstOrNull { it.name == "initialize" && it.parameterTypes.size == 1 }
                        if (init1 != null) {
                            init1.invoke(runtimeBridge, context)
                        } else {
                            call("initialize", context, emptyMap<String, Any?>())
                        }
                    }
                    "loadPlugin" -> {
                        val path = call.argument<String>("path") ?: return@launch withContext(Dispatchers.Main) {
                            result.error("INVALID_ARG", "path required", null)
                        }
                        cachedProviders = null
                        call("csLoadPlugin", context, path)
                        getRegisteredProvidersList()
                    }
                    "getRegisteredProviders" -> {
                        getRegisteredProvidersList()
                    }
                    "search" -> {
                        val api = cleanApiName(call.argument<String>("apiName"))
                        val params = call.argument<Map<String, Any?>>("parameters") ?: emptyMap<String, Any?>()
                        call("csSearch", context,
                            call.argument<String>("query") ?: "",
                            api,
                            call.argument<Int>("page") ?: 1,
                            params
                        )
                    }
                    "getDetail" -> {
                        val api = cleanApiName(call.argument<String>("apiName"))
                        val params = call.argument<Map<String, Any?>>("parameters") ?: emptyMap<String, Any?>()
                        call("csGetDetail", context,
                            api,
                            call.argument<String>("url") ?: "",
                            params
                        )
                    }
                    "getVideoList" -> {
                        val api = cleanApiName(call.argument<String>("apiName"))
                        val params = call.argument<Map<String, Any?>>("parameters") ?: emptyMap<String, Any?>()
                        call("csGetVideoList", context,
                            api,
                            call.argument<String>("url") ?: "",
                            params
                        )
                    }
                    "deletePlugin" -> {
                        val internalName = call.argument<String>("internalName") ?: return@launch withContext(Dispatchers.Main) {
                            result.error("INVALID_ARG", "internalName required", null)
                        }
                        cachedProviders = null
                        call("csUnloadPlugin", cleanApiName(internalName))
                    }
                    else -> {
                        withContext(Dispatchers.Main) { result.notImplemented() }
                        return@launch
                    }
                }
                withContext(Dispatchers.Main) { result.success(res) }
            } catch (e: Throwable) {
                if (e is kotlinx.coroutines.CancellationException) {
                    // Job was cancelled by user exiting watch screen - ignore silently
                    withContext(NonCancellable + Dispatchers.Main) {
                        try {
                            result.success(null)
                        } catch (_: Throwable) {}
                    }
                } else {
                    withContext(Dispatchers.Main) {
                        result.error("BRIDGE_ERROR", e.message, Log.getStackTraceString(e))
                    }
                }
            } finally {
                coroutineContext[Job]?.let { activeJobs.remove(it) }
            }
        }
        activeJobs.add(job)
    }

    private fun getRegisteredProvidersList(): List<Map<String, Any?>> {
        val cached = cachedProviders
        if (cached != null) return cached
        return try {
            val rawList = (call("csGetRegisteredProviders") as? List<*>) ?: return emptyList()
            val list = rawList.mapNotNull { item ->
                if (item == null) return@mapNotNull null
                val cls = item.javaClass
                fun getVal(name: String): String? {
                    return try {
                        val getterName = "get" + name.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
                        val m = cls.methods.firstOrNull { it.name.equals(name, ignoreCase = true) || it.name == getterName }
                        m?.invoke(item)?.toString()
                    } catch (_: Throwable) {
                        try {
                            val f = cls.fields.firstOrNull { it.name.equals(name, ignoreCase = true) }
                            f?.get(item)?.toString()
                        } catch (_: Throwable) {
                            null
                        }
                    }
                }

                val id = getVal("id")
                val name = getVal("name")
                val internalName = getVal("internalName")
                val mainUrl = getVal("mainUrl")
                val lang = getVal("lang")
                val sourcePlugin = getVal("sourcePlugin")
                val iconUrl = getVal("iconUrl")

                mapOf(
                    "id" to (id ?: internalName ?: name),
                    "name" to (name ?: id),
                    "internalName" to (internalName ?: id),
                    "mainUrl" to mainUrl,
                    "lang" to lang,
                    "sourcePlugin" to sourcePlugin,
                    "iconUrl" to iconUrl
                )
            }
            cachedProviders = list
            list
        } catch (e: Throwable) {
            Log.w(TAG, "Error getting registered providers: ${e.message}")
            emptyList()
        }
    }

    private fun cleanApiName(raw: String?): String {
        if (raw.isNullOrBlank()) return ""
        var s = raw.trim()
        if (s.startsWith("cs_", ignoreCase = true)) {
            s = s.substring(3)
        }

        try {
            val providers = getRegisteredProvidersList()
            if (providers.isNotEmpty()) {
                val sLower = s.lowercase()
                val sStripped = sLower.replace(Regex("(?i)provider|plugin|scraper"), "").trim()

                // 1. Exact match by id, internalName, or name
                val exact = providers.firstOrNull { p ->
                    val pId = (p["id"] as? String)?.lowercase()?.trim()
                    val pInternal = (p["internalName"] as? String)?.lowercase()?.trim()
                    val pName = (p["name"] as? String)?.lowercase()?.trim()
                    pId == sLower || pInternal == sLower || pName == sLower ||
                    (pId != null && pId.removePrefix("cs_") == sLower)
                }
                if (exact != null) {
                    val resolved = (exact["internalName"] as? String) ?: (exact["name"] as? String) ?: (exact["id"] as? String)
                    if (!resolved.isNullOrBlank()) return resolved
                }

                // 2. Stripped match (e.g. "MovieBoxProvider" -> "MovieBox", "AllMovieLandProvider" -> "AllMovieLand")
                if (sStripped.isNotEmpty()) {
                    val strippedMatch = providers.firstOrNull { p ->
                        val pId = (p["id"] as? String)?.lowercase()?.trim()
                        val pInternal = (p["internalName"] as? String)?.lowercase()?.trim()
                        val pName = (p["name"] as? String)?.lowercase()?.trim()
                        val pNameStripped = pName?.replace(Regex("(?i)provider|plugin|scraper"), "")?.trim()
                        pName == sStripped || pInternal == sStripped || pNameStripped == sStripped ||
                        (pId != null && pId.removePrefix("cs_") == sStripped)
                    }
                    if (strippedMatch != null) {
                        val resolved = (strippedMatch["internalName"] as? String) ?: (strippedMatch["name"] as? String) ?: (strippedMatch["id"] as? String)
                        if (!resolved.isNullOrBlank()) return resolved
                    }
                }
            }
        } catch (_: Throwable) {}

        return s
    }

    private fun handleVideoStream(apiName: String, url: String, parameters: Map<String, Any?>?, events: EventChannel.EventSink?) {
        videoStreamJob?.cancel()
        videoStreamJob = scope.launch {
            val active = java.util.concurrent.atomic.AtomicBoolean(true)
            val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

            try {
                val cls = bridgeClass ?: throw IllegalStateException("Runtime Host not loaded")
                val loader = cls.classLoader ?: throw IllegalStateException("No Host ClassLoader")
                val function1Class = loader.loadClass("kotlin.jvm.functions.Function1")
                val unitClass = loader.loadClass("kotlin.Unit")
                val unitInstance = unitClass.getField("INSTANCE").get(null)

                val proxyCallback = Proxy.newProxyInstance(
                    loader,
                    arrayOf(function1Class),
                    InvocationHandler { _, method, args ->
                        if (method?.name == "invoke" && active.get()) {
                            val video = args?.get(0)
                            mainHandler.post {
                                try { events?.success(video) } catch (_: Exception) {}
                            }
                            return@InvocationHandler unitInstance
                        }
                        null
                    }
                )

                call("csGetVideoListStream", context, apiName, url, proxyCallback, parameters)

                active.set(false)
                mainHandler.post {
                    events?.endOfStream()
                }
            } catch (e: Throwable) {
                active.set(false)
                withContext(Dispatchers.Main) {
                    events?.error("STREAM_ERROR", e.message, Log.getStackTraceString(e))
                    events?.endOfStream()
                }
            }
        }
    }

    private fun call(methodName: String, vararg args: Any?): Any? {
        val bridge = runtimeBridge ?: throw IllegalStateException("Runtime Host not loaded")
        val cls = bridgeClass ?: throw IllegalStateException("Runtime Host class not loaded")

        val method = cls.methods.firstOrNull { it.name == methodName && it.parameterTypes.size == args.size }
            ?: cls.methods.firstOrNull { it.name == methodName }
            ?: throw NoSuchMethodException("No method '$methodName' in RuntimeBridge")

        val effectiveArgs = if (method.parameterTypes.size != args.size) {
            if (args.size > method.parameterTypes.size) {
                args.take(method.parameterTypes.size).toTypedArray()
            } else {
                val padded = args.toMutableList()
                while (padded.size < method.parameterTypes.size) padded.add(null)
                padded.toTypedArray()
            }
        } else {
            args
        }

        return method.invoke(bridge, *effectiveArgs)
    }

    fun destroy() {
        videoStreamJob?.cancel()
        videoStreamJob = null
        activeJobs.forEach { it.cancel() }
        activeJobs.clear()
        scope.cancel()
    }
}
