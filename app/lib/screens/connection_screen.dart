import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';
import '../constants.dart';
import '../utils/validators.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController =
      TextEditingController(text: FarmLensConstants.defaultDevicePort);
  final _apiKeyController = TextEditingController();
  List<String> _recentUrls = [];
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(FarmLensConstants.prefKeyBaseUrl) ?? '';
    final recents =
        prefs.getStringList(FarmLensConstants.prefKeyRecentUrls) ?? [];

    final savedKey = prefs.getString(FarmLensConstants.prefKeyApiKey) ?? '';
    if (mounted) _apiKeyController.text = savedKey;
    if (saved.isNotEmpty) {
      final uri = Uri.tryParse(saved);
      if (uri != null && mounted) {
        _ipController.text = uri.host;
        _portController.text = uri.port.toString();
      }
    }
    if (mounted) {
      setState(() => _recentUrls = recents.take(3).toList());
    }
  }

  Future<void> _saveRecent(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final recents =
        prefs.getStringList(FarmLensConstants.prefKeyRecentUrls) ?? [];
    recents.remove(url);
    recents.insert(0, url);
    await prefs.setStringList(
        FarmLensConstants.prefKeyRecentUrls, recents.take(3).toList());
  }

  void _fillFromRecent(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      _ipController.text = uri.host;
      _portController.text = uri.port.toString();
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// Accepts dotted-decimal IPv4 addresses and hostnames (farmlens.local)
  String? _validateIp(String? value) => validateHost(value);

  String? _validatePort(String? value) => validatePort(value);

  /// Fills the form with the stable mDNS hostname - no IP hunting required
  void _useHostname() {
    setState(() {
      _ipController.text = 'farmlens.local';
      _portController.text = FarmLensConstants.defaultDevicePort;
    });
  }

  Future<void> _handleConnect() async {
    if (!_formKey.currentState!.validate()) return;

    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    final baseUrl = 'http://$ip:$port';

    setState(() => _isConnecting = true);

    final connProvider =
        Provider.of<ConnectionProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    final success = await connProvider.connect(baseUrl);

    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      await settingsProvider.saveDeviceUrl(baseUrl,
          apiKey: _apiKeyController.text.trim());
      await _saveRecent(baseUrl);
      if (!mounted) return;
      context.go('/main');
    } else {
      final err = connProvider.errorMessage ?? 'Could not connect to device';
      String message = err;
      if (err.toLowerCase().contains('socket') ||
          err.toLowerCase().contains('network')) {
        message = 'Check the phone and the node are on the same network';
      } else if (err.toLowerCase().contains('timeout')) {
        message =
            'Node not responding after ${FarmLensConstants.apiTimeoutSeconds} seconds';
      } else if (ip.contains('.local')) {
        message =
            'Could not reach $ip. Check the node is on the same network, or use its IP address';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: FarmLensColors.alert,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          color: FarmLensColors.textSecondary, fontSize: 14),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FarmLensColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FarmLensColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:
            const BorderSide(color: FarmLensColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FarmLensColors.alert),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:
            const BorderSide(color: FarmLensColors.alert, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FarmLensColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),

                  // ── Top Section ──────────────────────────────
                  const Icon(
                    Icons.eco_rounded,
                    size: 48,
                    color: FarmLensColors.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'FarmLens',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: FarmLensColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Crop health monitoring prototype',
                    style: TextStyle(
                      fontSize: 14,
                      color: FarmLensColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── mDNS Quick-Connect Banner ─────────────────
                  GestureDetector(
                    onTap: _useHostname,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: FarmLensColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: FarmLensColors.primary.withAlpha(60),
                            width: 1),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.wifi_find,
                              size: 18, color: FarmLensColors.primary),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Use farmlens.local  (recommended)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: FarmLensColors.primary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Connects by hostname - works even when the IP changes',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: FarmLensColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              size: 12, color: FarmLensColors.primary),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Divider ──────────────────────────────────
                  const Row(
                    children: [
                      Expanded(child: Divider(color: FarmLensColors.border)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'or enter manually',
                          style: TextStyle(
                            fontSize: 11,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: FarmLensColors.border)),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Form Card ────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: FarmLensColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: FarmLensColors.border, width: 0.5),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Device IP Address or Hostname',
                          style: TextStyle(
                            fontSize: 12,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _ipController,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          validator: _validateIp,
                          style: const TextStyle(
                            fontSize: 14,
                            color: FarmLensColors.textPrimary,
                          ),
                          decoration:
                              _fieldDecoration('Node IP address  or  farmlens.local'),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Port',
                          style: TextStyle(
                            fontSize: 12,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          validator: _validatePort,
                          style: const TextStyle(
                            fontSize: 14,
                            color: FarmLensColors.textPrimary,
                          ),
                          decoration:
                              _fieldDecoration(FarmLensConstants.defaultDevicePort),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The Raspberry Pi node serves the API on port 8000',
                          style: TextStyle(
                            fontSize: 11,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'API key (optional)',
                          style: TextStyle(
                            fontSize: 12,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          key: const Key('api-key-field'),
                          controller: _apiKeyController,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(
                            fontSize: 14,
                            color: FarmLensColors.textPrimary,
                          ),
                          decoration: _fieldDecoration(
                              'Only if API_KEY is set on the node'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Connect Button ───────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isConnecting ? null : _handleConnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FarmLensColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            FarmLensColors.primary.withAlpha(153),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Connect →',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  // ── Recent IPs ───────────────────────────────
                  if (_recentUrls.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          'Recent:',
                          style: TextStyle(
                            fontSize: 12,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            children: _recentUrls.map((url) {
                              final uri = Uri.tryParse(url);
                              final label = uri != null
                                  ? '${uri.host}:${uri.port}'
                                  : url;
                              return ActionChip(
                                label: Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: FarmLensColors.primary,
                                  ),
                                ),
                                onPressed: () => _fillFromRecent(url),
                                backgroundColor: Colors.transparent,
                                side: const BorderSide(
                                    color: FarmLensColors.primary, width: 1),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // ── Footer ───────────────────────────────────
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}