import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/settings/settings_app_bar.dart';

class DebridSettingsPage extends StatefulWidget {
  const DebridSettingsPage({super.key});

  @override
  State<DebridSettingsPage> createState() => _DebridSettingsPageState();
}

class _DebridSettingsPageState extends State<DebridSettingsPage> {
  final _debrid = DebridService();
  bool _useDebrid = false;
  String _selectedService = 'None';

  final _rdKeyCtrl = TextEditingController();
  final _torboxKeyCtrl = TextEditingController();
  final _alldebridKeyCtrl = TextEditingController();
  final _premiumizeKeyCtrl = TextEditingController();
  final _debridlinkKeyCtrl = TextEditingController();

  final Map<String, bool> _obscuredMap = {
    'Real-Debrid': true,
    'TorBox': true,
    'AllDebrid': true,
    'Premiumize': true,
    'Debrid-Link': true,
  };

  final Map<String, String?> _statusMap = {};
  final Map<String, bool> _loadingMap = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  String _sanitizeKey(String raw) {
    var s = raw.trim();
    if (s.startsWith('Bearer ')) s = s.substring(7).trim();
    if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  Future<void> _loadSettings() async {
    final useDebrid = await _debrid.getUseDebridForStreams();
    final service = await _debrid.getSelectedService();
    final rd = await _debrid.realDebrid.getToken() ?? '';
    final tb = await _debrid.torBox.getKey() ?? '';
    final ad = await _debrid.allDebrid.getKey() ?? '';
    final pm = await _debrid.premiumize.getKey() ?? '';
    final dl = await _debrid.debridLink.getKey() ?? '';

    _rdKeyCtrl.text = rd;
    _torboxKeyCtrl.text = tb;
    _alldebridKeyCtrl.text = ad;
    _premiumizeKeyCtrl.text = pm;
    _debridlinkKeyCtrl.text = dl;

    if (mounted) {
      setState(() {
        _useDebrid = useDebrid;
        _selectedService = service;
      });
    }

    // Verify existing keys in background
    if (rd.isNotEmpty) {
      _verifyKeySilent('Real-Debrid', rd);
    }
    if (tb.isNotEmpty) {
      _verifyKeySilent('TorBox', tb);
    }
    if (ad.isNotEmpty) {
      _verifyKeySilent('AllDebrid', ad);
    }
    if (pm.isNotEmpty) {
      _verifyKeySilent('Premiumize', pm);
    }
    if (dl.isNotEmpty) {
      _verifyKeySilent('Debrid-Link', dl);
    }
  }

  Future<void> _verifyKeySilent(String provider, String key) async {
    final cleaned = _sanitizeKey(key);
    if (cleaned.isEmpty) return;

    try {
      String? username;
      if (provider == 'Real-Debrid') {
        final res = await _debrid.realDebrid.verifyToken(cleaned);
        username = res?['username'] as String?;
      } else if (provider == 'TorBox') {
        final res = await _debrid.torBox.verifyKey(cleaned);
        username = (res?['email'] ?? res?['username']) as String?;
      } else if (provider == 'AllDebrid') {
        final res = await _debrid.allDebrid.verifyKey(cleaned);
        username = res?['username'] as String?;
      } else if (provider == 'Premiumize') {
        final res = await _debrid.premiumize.verifyKey(cleaned);
        username = res != null ? 'Connected' : null;
      } else if (provider == 'Debrid-Link') {
        final res = await _debrid.debridLink.verifyKey(cleaned);
        username = res?['username'] as String?;
      }

      if (mounted && username != null) {
        setState(() {
          _statusMap[provider] = username;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveProviderKey(String provider, TextEditingController controller) async {
    final key = _sanitizeKey(controller.text);
    controller.text = key;

    setState(() {
      _loadingMap[provider] = true;
    });

    if (key.isNotEmpty) {
      // Save key
      if (provider == 'Real-Debrid') {
        await _debrid.realDebrid.saveToken(key);
      } else if (provider == 'TorBox') {
        await _debrid.torBox.saveKey(key);
      } else if (provider == 'AllDebrid') {
        await _debrid.allDebrid.saveKey(key);
      } else if (provider == 'Premiumize') {
        await _debrid.premiumize.saveKey(key);
      } else if (provider == 'Debrid-Link') {
        await _debrid.debridLink.saveKey(key);
      }

      // Auto-enable Debrid and set as active service
      await _debrid.saveUseDebridForStreams(true);
      await _debrid.saveSelectedService(provider);
      await DebridService.refreshDebridReady();

      String? verifiedUser;
      if (provider == 'Real-Debrid') {
        final user = await _debrid.realDebrid.verifyToken(key);
        verifiedUser = user?['username'] as String?;
      } else if (provider == 'TorBox') {
        final user = await _debrid.torBox.verifyKey(key);
        verifiedUser = (user?['email'] ?? user?['username']) as String?;
      } else if (provider == 'AllDebrid') {
        final user = await _debrid.allDebrid.verifyKey(key);
        verifiedUser = user?['username'] as String?;
      } else if (provider == 'Premiumize') {
        final user = await _debrid.premiumize.verifyKey(key);
        verifiedUser = user != null ? 'Connected' : null;
      } else if (provider == 'Debrid-Link') {
        final user = await _debrid.debridLink.verifyKey(key);
        verifiedUser = user?['username'] as String?;
      }

      if (!mounted) return;
      setState(() {
        _useDebrid = true;
        _selectedService = provider;
        _statusMap[provider] = verifiedUser ?? 'Saved';
        _loadingMap[provider] = false;
      });

      if (verifiedUser != null) {
        _showSnack('$provider key verified ($verifiedUser) & set as active provider!');
      } else {
        _showSnack('$provider key saved & set as active provider!');
      }
    } else {
      // Clear key
      if (provider == 'Real-Debrid') {
        await _debrid.realDebrid.saveToken('');
      } else if (provider == 'TorBox') {
        await _debrid.torBox.saveKey('');
      } else if (provider == 'AllDebrid') {
        await _debrid.allDebrid.saveKey('');
      } else if (provider == 'Premiumize') {
        await _debrid.premiumize.saveKey('');
      } else if (provider == 'Debrid-Link') {
        await _debrid.debridLink.saveKey('');
      }

      if (_selectedService == provider) {
        await _debrid.saveSelectedService('None');
      }
      await DebridService.refreshDebridReady();

      if (!mounted) return;
      setState(() {
        if (_selectedService == provider) _selectedService = 'None';
        _statusMap.remove(provider);
        _loadingMap[provider] = false;
      });

      _showSnack('$provider key cleared.');
    }
  }

  Future<void> _pasteToController(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      final sanitized = _sanitizeKey(data.text!);
      controller.text = sanitized;
      _showSnack('Pasted key from clipboard');
    }
  }

  @override
  void dispose() {
    _rdKeyCtrl.dispose();
    _torboxKeyCtrl.dispose();
    _alldebridKeyCtrl.dispose();
    _premiumizeKeyCtrl.dispose();
    _debridlinkKeyCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final tokens = context.tokens;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: ZplayType.subtitle.toStyle()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? tokens.danger : tokens.accent,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: tokens.onAccent,
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const services = [
      'None',
      'Real-Debrid',
      'TorBox',
      'AllDebrid',
      'Premiumize',
      'Debrid-Link',
    ];

    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const SettingsAppBar(title: 'Debrid & Cloud Streaming'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // Header description
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'Stream torrents and magnet links instantly through high-speed cloud debrid providers without local peer-to-peer downloading.',
                  style: ZplayType.body.toStyle(color: tokens.textSecondary),
                ),
              ),

              // Master Debrid Toggle Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.all(
                    color: _useDebrid
                        ? tokens.accent.withValues(alpha: ZplayOpacity.borderStrong)
                        : tokens.borderDefault,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: ZplayOpacity.borderStrong),
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: Icon(
                            Icons.cloud_download_rounded,
                            color: tokens.accent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Use Debrid for Streams',
                                style: ZplayType.subtitle.toStyle(
                                  color: tokens.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Route torrent links through cloud servers',
                                style: ZplayType.bodySmall.toStyle(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch.adaptive(
                          value: _useDebrid,
                          activeColor: tokens.accent,
                          onChanged: (val) async {
                            setState(() => _useDebrid = val);
                            await _debrid.saveUseDebridForStreams(val);
                            if (val) {
                              final service = _selectedService;
                              if (service == 'None') {
                                _showSnack(
                                  'Select an active Debrid provider and save your API key below.',
                                  isError: true,
                                );
                              } else {
                                final hasKey = await _debrid.hasKeyForService(service);
                                if (!hasKey) {
                                  _showSnack(
                                    '$service has no API key saved. Please enter and save your key below.',
                                    isError: true,
                                  );
                                } else {
                                  _showSnack('Debrid streaming activated via $service');
                                }
                              }
                            } else {
                              _showSnack('Debrid streaming disabled. Using local engine.');
                            }
                            await DebridService.refreshDebridReady();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'When enabled, all torrents from ZPlay and Stremio addons are resolved exclusively through your active Debrid provider without touching the local torrent engine.',
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Active Provider Selector
              Text(
                'ACTIVE PROVIDER',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.fromBorderSide(tokens.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Default Debrid Provider',
                      style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ZPlay will send requests to this provider when streaming.',
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: services.contains(_selectedService) ? _selectedService : 'None',
                      dropdownColor: tokens.surfaceOverlay,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: tokens.bg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: ZplayRadius.smAll,
                          borderSide: BorderSide(color: tokens.borderDefault),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: ZplayRadius.smAll,
                          borderSide: BorderSide(color: tokens.borderDefault),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: ZplayRadius.smAll,
                          borderSide: BorderSide(color: tokens.accent),
                        ),
                      ),
                      style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                      items: services.map((s) {
                        return DropdownMenuItem<String>(
                          value: s,
                          child: Row(
                            children: [
                              Icon(
                                s == 'None' ? Icons.block_rounded : Icons.flash_on_rounded,
                                size: 16,
                                color: s == 'None' ? tokens.textMuted : tokens.accent,
                              ),
                              const SizedBox(width: 8),
                              Text(s),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() => _selectedService = val);
                          await _debrid.saveSelectedService(val);
                          await DebridService.refreshDebridReady();
                          if (val != 'None') {
                            final hasKey = await _debrid.hasKeyForService(val);
                            if (!hasKey) {
                              _showSnack(
                                '$val selected, but has no API key saved yet. Please enter and save your key below.',
                              );
                              return;
                            }
                          }
                          _showSnack('Active Debrid service set to $val');
                        }
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Provider API Keys
              Text(
                'PROVIDER CREDENTIALS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 10),

              // Real-Debrid Card
              _buildProviderCard(
                name: 'Real-Debrid',
                subtitle: _statusMap['Real-Debrid'] != null
                    ? 'Logged in as ${_statusMap['Real-Debrid']}'
                    : 'Get token from real-debrid.com/apitoken',
                statusBadge: _statusMap['Real-Debrid'],
                badgeColor: tokens.success,
                controller: _rdKeyCtrl,
                isLoading: _loadingMap['Real-Debrid'] == true,
                isActive: _selectedService == 'Real-Debrid',
                onSave: () => _saveProviderKey('Real-Debrid', _rdKeyCtrl),
              ),
              const SizedBox(height: 12),

              // TorBox Card
              _buildProviderCard(
                name: 'TorBox',
                subtitle: _statusMap['TorBox'] != null
                    ? 'Account: ${_statusMap['TorBox']}'
                    : 'Get key from torbox.app/settings',
                statusBadge: _statusMap['TorBox'],
                badgeColor: tokens.success,
                controller: _torboxKeyCtrl,
                isLoading: _loadingMap['TorBox'] == true,
                isActive: _selectedService == 'TorBox',
                onSave: () => _saveProviderKey('TorBox', _torboxKeyCtrl),
              ),
              const SizedBox(height: 12),

              // AllDebrid Card
              _buildProviderCard(
                name: 'AllDebrid',
                subtitle: _statusMap['AllDebrid'] != null
                    ? 'Account: ${_statusMap['AllDebrid']}'
                    : 'Get key from alldebrid.com/apikeys',
                statusBadge: _statusMap['AllDebrid'],
                badgeColor: tokens.success,
                controller: _alldebridKeyCtrl,
                isLoading: _loadingMap['AllDebrid'] == true,
                isActive: _selectedService == 'AllDebrid',
                onSave: () => _saveProviderKey('AllDebrid', _alldebridKeyCtrl),
              ),
              const SizedBox(height: 12),

              // Premiumize Card
              _buildProviderCard(
                name: 'Premiumize',
                subtitle: _statusMap['Premiumize'] != null
                    ? 'Account: Connected'
                    : 'Get key from premiumize.me/account',
                statusBadge: _statusMap['Premiumize'],
                badgeColor: tokens.success,
                controller: _premiumizeKeyCtrl,
                isLoading: _loadingMap['Premiumize'] == true,
                isActive: _selectedService == 'Premiumize',
                onSave: () => _saveProviderKey('Premiumize', _premiumizeKeyCtrl),
              ),
              const SizedBox(height: 12),

              // Debrid-Link Card
              _buildProviderCard(
                name: 'Debrid-Link',
                subtitle: _statusMap['Debrid-Link'] != null
                    ? 'Account: ${_statusMap['Debrid-Link']}'
                    : 'Get key from debrid-link.com/webapp/apikey',
                statusBadge: _statusMap['Debrid-Link'],
                badgeColor: tokens.success,
                controller: _debridlinkKeyCtrl,
                isLoading: _loadingMap['Debrid-Link'] == true,
                isActive: _selectedService == 'Debrid-Link',
                onSave: () => _saveProviderKey('Debrid-Link', _debridlinkKeyCtrl),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderCard({
    required String name,
    required String subtitle,
    required TextEditingController controller,
    required VoidCallback onSave,
    bool isActive = false,
    bool isLoading = false,
    String? statusBadge,
    Color? badgeColor,
  }) {
    final tokens = context.tokens;
    final isObscured = _obscuredMap[name] ?? true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(
          color: isActive
              ? tokens.accent.withValues(alpha: ZplayOpacity.borderStrong)
              : tokens.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                name,
                style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: ZplayOpacity.borderStrong),
                    borderRadius: ZplayRadius.xsAll,
                  ),
                  child: Text(
                    'ACTIVE',
                    style: ZplayType.caption.toStyle(color: tokens.accent),
                  ),
                ),
              if (statusBadge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? tokens.success).withValues(
                      alpha: ZplayOpacity.borderStrong,
                    ),
                    borderRadius: ZplayRadius.xsAll,
                  ),
                  child: Text(
                    statusBadge,
                    style: ZplayType.caption.toStyle(
                      color: badgeColor ?? tokens.success,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: isObscured,
                  style: ZplayType.label.toStyle(color: tokens.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Paste API Key / Token',
                    hintStyle: ZplayType.bodySmall.toStyle(
                      color: tokens.textDisabled,
                    ),
                    filled: true,
                    fillColor: tokens.bg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: ZplayRadius.smAll,
                      borderSide: BorderSide(color: tokens.borderDefault),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: ZplayRadius.smAll,
                      borderSide: BorderSide(color: tokens.borderDefault),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: ZplayRadius.smAll,
                      borderSide: BorderSide(color: tokens.accent),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (controller.text.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.clear_rounded, color: tokens.textMuted, size: 16),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            tooltip: 'Clear',
                            onPressed: () {
                              controller.clear();
                              setState(() {});
                            },
                          ),
                        IconButton(
                          icon: Icon(
                            isObscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: tokens.textMuted,
                            size: 16,
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: isObscured ? 'Show Key' : 'Hide Key',
                          onPressed: () {
                            setState(() {
                              _obscuredMap[name] = !isObscured;
                            });
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.content_paste_rounded, color: tokens.accent, size: 16),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: 'Paste from Clipboard',
                          onPressed: () => _pasteToController(controller),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isLoading ? null : onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.onAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                  elevation: 0,
                ),
                child: isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: tokens.onAccent),
                      )
                    : Text(
                        'Save',
                        style: ZplayType.label.toStyle(),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
