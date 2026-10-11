package io.github.tzero86.zplay

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Voice search on the platform's own recognizer.
 *
 * The app ships no recognizer: it launches whichever one the device already has
 * through [RecognizerIntent.ACTION_RECOGNIZE_SPEECH], lets that activity own the
 * microphone, and takes back only the first transcript. That is deliberate. A
 * bundled recognizer would mean shipping an acoustic model and a hotword the
 * user never asked for, and a television already has the one the OEM tuned for
 * its far-field remote.
 *
 * **Activity-level results, not `ActivityResultLauncher`.** The modern
 * `registerForActivityResult` API lives on `androidx.activity.ComponentActivity`,
 * and this app's `MainActivity` is a `FlutterActivity`, which extends plain
 * `android.app.Activity`. Moving the app onto `FlutterFragmentActivity` to reach
 * that API would change fragment hosting, keyboard insets and every other
 * plugin's registration in the shipping activity, which is not a risk a
 * microphone button should buy. So the callbacks come in the same way Flutter's
 * own channel plugins receive them: the activity overrides `onActivityResult`
 * and `onRequestPermissionsResult`, forwards them here, and calls `super` for
 * anything this bridge does not claim.
 *
 * Two failure modes have a name, and the Dart side switches on them:
 * `denied` when the microphone permission was refused, `unavailable` when the
 * device has no activity to show. `busy` is the guard against a second `listen`
 * while one is in flight - it is a rejected attempt, not a broken feature, so the
 * caller leaves the control where it is.
 */
class VoiceSearchBridge(
    private val context: Context,
    private val activity: Activity,
) {

    private companion object {
        const val TAG = "VoiceSearch"
        const val METHOD_CHANNEL = "io.github.tzero86.zplay/voice_search"

        /** Owns [Activity.onActivityResult]; no other request code may use it. */
        const val REQ_SPEECH = 4711

        /** Owns [Activity.onRequestPermissionsResult] for the same reason. */
        const val REQ_MIC = 4712
    }

    /**
     * The one `listen` still waiting for an answer.
     *
     * Held as the MethodChannel.Result itself rather than a completer, because
     * a MethodChannel result may be completed exactly once and every path out of
     * here - a result, a cancel, a refusal, the activity dying - must be the one
     * that completes it. It is nulled before completing so a late callback
     * (a permission result arriving after destroy, say) cannot complete it twice.
     */
    private var pendingResult: MethodChannel.Result? = null

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isRecognitionAvailable())
                    "listen" -> startListening(result)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Whether this request code is ours, and what came back for it.
     *
     * Returns true when the bridge claimed the callback, so `MainActivity`
     * knows not to pass it on. The recognizer activity is the app's only
     * `startActivityForResult` caller with this code, but the result must still
     * be reported as claimed even if the pending call already went away - the
     * request code alone says it was ours.
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_SPEECH) return false

        val pending = pendingResult ?: return true
        pendingResult = null

        if (resultCode != Activity.RESULT_OK) {
            // RESULT_CANCELED covers the user backing out without speaking,
            // which is a cancellation rather than an empty query: Dart is told
            // null and leaves the search field untouched.
            pending.success(null)
            return true
        }

        val transcript = data
            ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            ?.firstOrNull()
            ?.trim()
        // A recognizer that heard silence returns an empty first result; that is
        // no transcript, so it is reported the same as a cancel.
        pending.success(if (transcript.isNullOrEmpty()) null else transcript)
        return true
    }

    /**
     * The microphone permission answer, on the same terms.
     *
     * A granted result resumes the recognition that was waiting; a refusal
     * completes it as `denied` rather than leaving Dart holding a future that
     * can never resolve.
     */
    fun handlePermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQ_MIC) return false

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) dispatchListen() else failPending("denied")
        return true
    }

    /**
     * Complete a `listen` still open when the activity goes away.
     *
     * Registered from `MainActivity.onDestroy`. Without this the Dart future
     * would hang forever if the page is torn down while the recognizer activity
     * is still open - and a hung future holds the platform call open too.
     */
    fun destroy() {
        pendingResult?.success(null)
        pendingResult = null
    }

    /**
     * Both halves of "can this device listen?".
     *
     * The manifest declares `android.speech.RecognitionService` and
     * `android.speech.action.RECOGNIZE_SPEECH` under `<queries>`, because from
     * API 30 the platform hides both the service and the activity from an app
     * that has not asked for them - and a hidden activity resolves to null,
     * which would turn a working television into "no recognizer".
     */
    private fun isRecognitionAvailable(): Boolean {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) return false
        return recognitionIntent().resolveActivity(context.packageManager) != null
    }

    private fun recognitionIntent(): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            // One result: the field takes a single query, and a list would only
            // give the user a picker between near-identical guesses.
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            // No partials: the search must run on the finished sentence, not on
            // every half-word the recognizer revises.
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to search ZPlay")
        }

    private fun startListening(result: MethodChannel.Result) {
        // One at a time. A second call while the recognizer activity is up would
        // need a second MethodChannel result that the single activity callback
        // could never route, so it is refused instead of stacked.
        if (pendingResult != null) {
            Log.w(TAG, "listen while one is still pending; refusing")
            result.error("busy", "a voice search is already in flight", null)
            return
        }
        if (!isRecognitionAvailable()) {
            result.error("unavailable", "no speech recognition activity", null)
            return
        }

        pendingResult = result
        if (ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            dispatchListen()
        } else {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                REQ_MIC
            )
        }
    }

    private fun dispatchListen() {
        // A permission answer can arrive after the pending call was already
        // completed (the page went away while the dialog was up); launching the
        // recognizer then would open an activity nobody is waiting on.
        if (pendingResult == null) return

        try {
            activity.startActivityForResult(recognitionIntent(), REQ_SPEECH)
        } catch (e: ActivityNotFoundException) {
            // isRecognitionAvailable already resolved the activity, but a device
            // can still change its mind between the check and the launch; the
            // caller must not be left holding a future that can never resolve.
            Log.w(TAG, "recognizer activity vanished before launch: ${e.message}")
            failPending("unavailable")
        }
    }

    private fun failPending(code: String) {
        val pending = pendingResult ?: return
        pendingResult = null
        pending.error(code, null, null)
    }
}
