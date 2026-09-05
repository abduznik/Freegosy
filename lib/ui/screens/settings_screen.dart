import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/platform/platform_info.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../core/storage/directory_service.dart';
import '../../core/storage/system_utils.dart';
import '../../providers/platform_info_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/shared_prefs_provider.dart';
import '../../providers/downloaded_games_cache_provider.dart';
import '../../core/romm/romm_service.dart';
import '../../core/romm/romm_models.dart';
import '../../core/storage/logger_service.dart';
import '../../core/error/error_handler.dart';
import 'settings_emulators_section.dart';
import 'settings_display_section.dart';
import 'settings_custom_emulators_section.dart';
import 'settings_controller_section.dart';
import 'settings_deadzone_section.dart';
import 'settings_retroachievements_section.dart';
import '../../core/constants/app_constants.dart';
import '../../core/emulator/retroarch_core_list.dart';
import '../../core/emulator/strategy_registry.dart';
import '../../providers/theme_provider.dart';
import '../widgets/focus_effect_wrapper.dart';
import '../widgets/dialog_back_bridge.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _baseUrlController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _apiKeyController;
  bool _preferencesLoaded = false;
  bool _isLegacyAuth = false;
  bool _trustSelfSigned = false;
  bool _isTestingConnection = false;
  AppError? _connectionAppError;
  String? _pairedToken;
  bool _isEditingServer = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _apiKeyController = TextEditingController();
    // Refresh emulator status when settings screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(emulatorStatusProvider);
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  InputDecoration _buildInputDecoration(BuildContext context, String label) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildCustomDropdown<T>({
    required BuildContext context,
    required String label,
    required T currentValue,
    required String currentValueLabel,
    required List<Map<String, dynamic>> items,
    required Function(T) onChanged,
  }) {
    final theme = Theme.of(context);
    return FocusEffectWrapper(
      onTap: () async {
        final selected = await showDialog<T>(
          context: context,
          builder: (ctx) => DialogBackBridge(
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text('Select $label'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: items.map((item) {
                  final isSelected = item['value'] == currentValue;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: FocusEffectWrapper(
                      onTap: () => Navigator.pop(ctx, item['value']),
                      borderRadius: 16.0,
                      autofocus: isSelected,
                      useSafeScale: false,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: isSelected 
                              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) 
                              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          border: Border.all(
                            color: isSelected 
                                ? theme.colorScheme.primary.withValues(alpha: 0.4) 
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_circle : Icons.radio_button_off,
                              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              size: 18,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              item['label'] as String,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              actions: [
                FocusEffectWrapper(
                  onTap: () => Navigator.pop(ctx),
                  borderRadius: 16.0,
                  useSafeScale: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                    ),
                    child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ),
              ],
            ),
          ),
        );
        if (selected != null) {
          onChanged(selected);
        }
      },
      borderRadius: 16.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              currentValueLabel,
              style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomToggleRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool)? onChanged,
  }) {
    final theme = Theme.of(context);
    final isEnabled = onChanged != null;
    return FocusEffectWrapper(
      onTap: !isEnabled ? null : () => onChanged(!value),
      borderRadius: 16.0,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
          ),
          child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: value ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: value ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                value ? 'ON' : 'OFF',
                style: TextStyle(
                  color: value ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
     ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              // ignore: use_null_aware_elements
              if (trailing != null) trailing,
            ],
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isPrimary = false,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    return FocusEffectWrapper(
      onTap: onTap,
      borderRadius: 16.0,
      scaleFactor: 1.005,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isPrimary
              ? LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isPrimary
              ? null
              : (isDestructive
                  ? Colors.red.withValues(alpha: 0.08)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
          border: Border.all(
            color: isPrimary
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : (isDestructive
                    ? Colors.red.withValues(alpha: 0.2)
                    : theme.colorScheme.outline.withValues(alpha: 0.3)),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isPrimary
                  ? theme.colorScheme.onPrimary
                  : (isDestructive ? Colors.redAccent : theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isPrimary
                    ? theme.colorScheme.onPrimary
                    : (isDestructive ? Colors.redAccent : theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathRow(
    BuildContext context, {
    required String label,
    required String currentPath,
    required Function(String?)? onChanged,
    VoidCallback? onReset,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  currentPath,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (onReset != null)
                FocusEffectWrapper(
                  onTap: onReset,
                  borderRadius: 12.0,
                  scaleFactor: 1.1,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.restore, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              if (onReset != null) const SizedBox(width: 8),
              if (onChanged != null)
                FocusEffectWrapper(
                  onTap: () async => onChanged(await FilePicker.platform.getDirectoryPath()),
                  borderRadius: 12.0,
                  scaleFactor: 1.005,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Change',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final directoryServiceAsync = ref.watch(directoryServiceProvider);
    final rommService = ref.watch(rommServiceProvider);
    final rommConfigAsync = ref.watch(rommConfigProvider);
    final strategyRegistry = ref.watch(strategyRegistryProvider).asData?.value;
    final emulatorStatusAsync = ref.watch(emulatorStatusProvider);

    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final columnCount = ref.watch(columnCountProvider);
    final cardSpacing = ref.watch(cardSpacingProvider);
    final showTitle = ref.watch(showTitleProvider);
    final activePreset = ref.watch(activePresetProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('freegosy_logo.png', height: 28, width: 28),
            const SizedBox(width: 12),
            const Text('Settings'),
          ],
        ),
      ),
      body: rommConfigAsync.when(
        data: (rommConfig) {
          if (!_preferencesLoaded) {
            _baseUrlController.text = rommConfig.baseUrl;
            _usernameController.text = rommConfig.username;
            _passwordController.text = rommConfig.password;
            _apiKeyController.text = rommConfig.apiKey;
            _isLegacyAuth = rommConfig.apiKey.isEmpty && 
                           (rommConfig.username.isNotEmpty || rommConfig.password.isNotEmpty);
            _trustSelfSigned = rommConfig.trustSelfSigned;
            _preferencesLoaded = true;
          }
          return directoryServiceAsync.when(
            data: (directoryService) {
              if (directoryService == null) return const Center(child: Text('Storage service not available.'));

              final theme = Theme.of(context);

              return ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildRommServerSection(context, ref, rommService, rommConfig),
                  const SettingsRetroAchievementsSection(),
                  _buildSectionCard(
                    context: context,
                    title: 'Controller Setup',
                    icon: Icons.gamepad,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SettingsControllerSection(),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text(
                          'Analog Deadzone',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ignores small stick drift near the center.',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const DeadzoneGlobalRow(),
                      ],
                    ),
                  ),
                  _buildAppearanceSection(context, ref),
                  _buildSectionCard(
                    context: context,
                    title: 'Library Display',
                    icon: Icons.grid_view,
                    child: buildDisplaySection(context, cardAspectRatio, columnCount, cardSpacing, showTitle, activePreset, ref),
                  ),
                  _buildStorageSection(context, directoryService),
                  if (ref.read(platformInfoProvider).isLinux) ...[
                    _buildLinuxSettingsSection(context, ref, directoryService),
                  ],
                   _buildSectionCard(
                    context: context,
                    title: 'Emulators',
                    icon: Icons.sports_esports,
                    child: emulatorStatusAsync.when(
                      data: (states) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildEmulatorsSection(context, directoryService, true, states, setState, ref),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 12),
                            const SettingsCustomEmulatorsSection(),
                            // Platform Manager: header + toggle always visible, list collapses when per-game ON
                            if (strategyRegistry != null) ...[
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 12),
                              buildConflictsSection(context, strategyRegistry, setState, ref),
                            ],
                          ],
                        ),
                      loading: () => buildEmulatorsSection(context, directoryService, false, {}, setState, ref),
                      error: (e, s) => Center(child: Text('Error: $e')),
                    ),
                  ),
                   _buildRetroArchSettingsSection(context, ref),
                   _buildLegalSection(context),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Error: $e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentTheme = ref.watch(themeProvider);
    final headerMode = ref.watch(libraryHeaderTitleModeProvider);
    return _buildSectionCard(
      context: context,
      title: 'Appearance & Customization',
      icon: Icons.palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose the overall visual style and header personalization of Freegosy.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildCustomDropdown<ThemePreset>(
            context: context,
            label: 'Active Theme',
            currentValue: currentTheme,
            currentValueLabel: currentTheme.displayName,
            items: ThemePreset.values.map((preset) => {
              'value': preset,
              'label': preset.displayName,
            }).toList(),
            onChanged: (preset) {
              ref.read(themeProvider.notifier).setTheme(preset);
            },
          ),
          const SizedBox(height: 16),
          _buildCustomDropdown<String>(
            context: context,
            label: 'Library Header Title',
            currentValue: headerMode,
            currentValueLabel: _getHeaderTitleModeLabel(headerMode),
            items: const [
              {'value': 'daily', 'label': 'Daily Game Recommendation'},
              {'value': 'session', 'label': 'Session Game Recommendation'},
              {'value': 'last_played', 'label': 'Last Played Game'},
              {'value': 'server_ip', 'label': 'Server URL / IP'},
              {'value': 'greetings', 'label': 'Fun Retro Greetings'},
              {'value': 'none', 'label': 'None / Just App Logo'},
            ],
            onChanged: (mode) {
              ref.read(libraryHeaderTitleModeProvider.notifier).update(mode);
            },
          ),
        ],
      ),
    );
  }

  String _getHeaderTitleModeLabel(String mode) {
    switch (mode) {
      case 'daily':
        return 'Daily Game Recommendation';
      case 'session':
        return 'Session Game Recommendation';
      case 'last_played':
        return 'Last Played Game';
      case 'server_ip':
        return 'Server URL / IP';
      case 'greetings':
        return 'Fun Retro Greetings';
      case 'none':
        return 'None / Just App Logo';
      default:
        return 'Daily Game Recommendation';
  }
  }


  Widget _buildRommServerSection(BuildContext context, WidgetRef ref, RommService? rommService, RomMConfig rommConfig) {
    final theme = Theme.of(context);
    return _buildSectionCard(
      context: context,
      title: 'RomM Server',
      icon: Icons.dns,
      trailing: FocusEffectWrapper(
        borderRadius: 24,
        scaleFactor: 1.1,
        useSafeScale: false,
        onTap: () {
          setState(() {
            _isEditingServer = !_isEditingServer;
          });
        },
        child: IconButton(
          icon: Icon(
            _isEditingServer ? Icons.lock_open : Icons.lock,
            color: _isEditingServer ? theme.colorScheme.primary : Colors.grey,
          ),
          tooltip: _isEditingServer ? 'Lock connection details' : 'Unlock connection details to edit',
          onPressed: () {
            setState(() {
              _isEditingServer = !_isEditingServer;
            });
          },
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _baseUrlController,
            readOnly: !_isEditingServer,
            obscureText: !_isEditingServer,
            decoration: _buildInputDecoration(context, 'Server URL'),
          ),
          const SizedBox(height: 16),
          if (_isLegacyAuth) ...[
            TextField(
              controller: _usernameController,
              readOnly: !_isEditingServer,
              obscureText: !_isEditingServer,
              decoration: _buildInputDecoration(context, 'Username'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              readOnly: !_isEditingServer,
              obscureText: true,
              decoration: _buildInputDecoration(context, 'Password'),
            ),
          ] else
            TextField(
              controller: _apiKeyController,
              readOnly: !_isEditingServer,
              obscureText: true,
              decoration: _buildInputDecoration(context, 'API Key (RomM 4.8+)'),
            ),
          const SizedBox(height: 16),
          _buildCustomToggleRow(
            context,
            title: 'Legacy Authentication',
            subtitle: 'Enable if your RomM server is below v4.8',
            value: _isLegacyAuth,
            onChanged: !_isEditingServer ? null : (val) => setState(() => _isLegacyAuth = val),
          ),
          const SizedBox(height: 16),
          _buildCustomToggleRow(
            context,
            title: 'Trust Self-Signed Certificates',
            subtitle: 'Enable if your RomM server uses a self-signed SSL certificate',
            value: _trustSelfSigned,
            onChanged: !_isEditingServer ? null : (val) => setState(() => _trustSelfSigned = val),
          ),
          const SizedBox(height: 16),
          if (_connectionAppError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: _connectionAppError!.technical != null
                    ? () => _showConnectionErrorDetails(context, _connectionAppError!)
                    : null,
                child: Text(
                  _connectionAppError!.message,
                  style: TextStyle(
                    color: _connectionAppError!.severity == ErrorSeverity.warning
                        ? Colors.orange
                        : theme.colorScheme.error,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    decoration: _connectionAppError!.technical != null
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  context,
                  icon: Icons.phonelink_setup,
                  label: 'Pair Device',
                  onTap: !_isEditingServer ? null : () => _showPairingDialog(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  context,
                  icon: _isTestingConnection ? Icons.hourglass_empty : Icons.network_ping,
                  label: _isTestingConnection ? 'Testing...' : 'Test Connection',
                  onTap: !_isEditingServer || _isTestingConnection ? null : () async {
                    final baseUrl = _baseUrlController.text.trim();
                    if (baseUrl.isEmpty) {
                      setState(() {
                        _connectionAppError = AppError(title: 'Missing URL', message: 'Server URL is required', severity: ErrorSeverity.warning);
                      });
                      return;
                    }

                    setState(() {
                      _isTestingConnection = true;
                      _connectionAppError = null;
                    });

                    try {
                      final testConfig = RomMConfig(
                        baseUrl: baseUrl,
                        username: _usernameController.text.trim(),
                        password: _passwordController.text,
                        apiKey: _pairedToken == null ? _apiKeyController.text.trim() : '',
                        token: _pairedToken,
                        trustSelfSigned: _trustSelfSigned,
                      );
                      
                      final testService = RommService(testConfig, skipConnectivityCheck: true);
                      await testService.getPlatforms();
                      
                      if (mounted) {
                        setState(() {
                          _isTestingConnection = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connection successful!')));
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          _isTestingConnection = false;
                          _connectionAppError = ErrorHandler.parse(e, context: 'Connection test');
                        });
                      }
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            context,
            icon: Icons.save,
            label: 'Save Configuration',
            onTap: !_isEditingServer ? null : () async {
              final prefs = ref.read(appPreferencesProvider);
              await prefs.setString('rommBaseUrl', _baseUrlController.text.trim());
              await prefs.setBool('rommTrustSelfSigned', _trustSelfSigned);
              if (_isLegacyAuth) {
                 await prefs.setString('rommUsername', _usernameController.text.trim());
                 await SecureStorageService.write('rommPassword', _passwordController.text, prefs);
                 await SecureStorageService.delete('rommApiKey', prefs);
                 await SecureStorageService.delete('rommAuthToken', prefs);
              } else if (_pairedToken != null) {
                 await SecureStorageService.write('rommAuthToken', _pairedToken!, prefs);
                 await SecureStorageService.delete('rommApiKey', prefs);
                 await prefs.setString('rommUsername', '');
                 await SecureStorageService.delete('rommPassword', prefs);
              } else {
                 await SecureStorageService.write('rommApiKey', _apiKeyController.text.trim(), prefs);
                 await SecureStorageService.delete('rommAuthToken', prefs);
                 await prefs.setString('rommUsername', '');
                 await SecureStorageService.delete('rommPassword', prefs);
              }
              _pairedToken = null;
              ref.invalidate(rommConfigProvider);
              ref.invalidate(rommServiceProvider);
              if (mounted) {
                setState(() {
                  _isEditingServer = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
              }
            },
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStorageSection(BuildContext context, DirectoryService directoryService) {
    final theme = Theme.of(context);
    final preset = directoryService.linuxSyncPreset;
    
    return _buildSectionCard(
      context: context,
      title: 'Storage',
      icon: Icons.folder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ref.read(platformInfoProvider).isLinux) ...[
            _buildCustomDropdown<String>(
              context: context,
              label: 'Linux App Layout',
              currentValue: preset,
              currentValueLabel: preset == 'default'
                  ? 'Manual / Native'
                  : (preset == 'emudeck' ? 'EmuDeck' : 'RetroDECK'),
              items: const [
                {'value': 'default', 'label': 'Manual / Native'},
                {'value': 'emudeck', 'label': 'EmuDeck'},
                {'value': 'retrodeck', 'label': 'RetroDECK'},
              ],
              onChanged: (val) async {
                await directoryService.setLinuxSyncPreset(val);
                ref.invalidate(directoryServiceProvider);
              },
            ),
            const SizedBox(height: 16),
          ],

          if (ref.read(platformInfoProvider).isLinux && (preset == 'emudeck' || preset == 'retrodeck')) ...[
            _buildPathRow(
              context,
              label: '${preset == 'emudeck' ? 'EmuDeck' : 'RetroDECK'} Installation Root',
              currentPath: directoryService.linuxPresetRootPath ?? 'Not set',
              onChanged: (p) async { 
                if (p != null) { 
                  await directoryService.setLinuxPresetRoot(p);
                  ref.invalidate(directoryServiceProvider); 
                } 
              },
            ),
            const SizedBox(height: 16),
          ],

          _buildPathRow(
            context,
            label: 'ROMs Directory',
            currentPath: directoryService.romsRootPath,
            onChanged: (p) async { 
              if (p != null) { 
                await directoryService.setRomsRoot(p); 
                ref.invalidate(directoryServiceProvider); 
              } 
            },
            onReset: () async { 
              await directoryService.resetRomsRoot(); 
              ref.invalidate(directoryServiceProvider); 
            },
          ),
          const SizedBox(height: 16),
          _buildPathRow(
            context,
            label: 'Emulators Directory',
            currentPath: directoryService.emulatorsRootPath,
            onChanged: (p) async { 
              if (p != null) { 
                await directoryService.setEmulatorsRoot(p); 
                ref.invalidate(directoryServiceProvider); 
              } 
            },
            onReset: () async { 
              await directoryService.resetEmulatorsRoot(); 
              ref.invalidate(directoryServiceProvider); 
            },
          ),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Flat Emulator Layout',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      const SizedBox(height: 2),
                      Text('Extract emulators directly into the root without per-emulator subfolders',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                SizedBox(
                  height: 32,
                  child: Switch.adaptive(
                    value: directoryService.useFlatEmulatorLayout,
                    onChanged: (val) async {
                      await directoryService.setUseFlatEmulatorLayout(val);
                      ref.invalidate(directoryServiceProvider);
                    },
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  context,
                  icon: Icons.folder_open,
                  label: 'Open ROMs',
                  onTap: () => SystemUtils.openDirectory(directoryService.romsRootPath),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  context,
                  icon: Icons.folder_shared,
                  label: 'Open App Data',
                  onTap: SystemUtils.openAppDataDirectory,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text('Troubleshooting', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
          const SizedBox(height: 4),
          Text('If games are missing from your offline library, try a full scan.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Consumer(builder: (context, ref, _) {
                  final isScanning = ref.watch(isScanningProvider);
                  return _buildActionButton(
                    context,
                    icon: Icons.sync,
                    label: isScanning ? 'Scanning...' : 'Force Full Scan',
                    onTap: isScanning ? null : () async {
                      await ref.read(downloadedGamesCacheProvider.notifier).startIncrementalSync(force: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full ROM scan complete.')));
                      }
                    },
                  );
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  context,
                  icon: Icons.receipt_long,
                  label: 'View Logs',
                  onTap: () => _showLogsDialog(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLogsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const DialogBackBridge(child: _LogsDialogContent()),
    );
  }

  Widget _buildRetroArchSettingsSection(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strategyRegistry = ref.watch(strategyRegistryProvider).asData?.value;
    final coreOverrides = strategyRegistry?.coreOverrides ?? {};

    return _buildSectionCard(
      context: context,
      title: 'RetroArch Cores',
      icon: Icons.extension,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set default cores per platform. Tap a platform to expand and choose.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Searchable platform list
          _buildAllCoresSection(context, ref, coreOverrides, strategyRegistry),

          const SizedBox(height: 16),

          // Reset button
          Row(
            children: [
              _buildActionButton(
                context,
                icon: Icons.restore,
                label: 'Reset All to Defaults',
                onTap: strategyRegistry != null ? () async {
                  await strategyRegistry.clearAllCoreOverrides();
                  setState(() {});
                } : null,
                isDestructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllCoresSection(
    BuildContext context,
    WidgetRef ref,
    Map<String, String> coreOverrides,
    StrategyRegistry? strategyRegistry,
  ) {
    final theme = Theme.of(context);
    final searchController = TextEditingController();

    // Collect all unique platform slugs with at least one compatible core
    final allPlatforms = <String>{};
    for (final core in kRetroArchCores) {
      allPlatforms.addAll(core.platforms);
    }
    final sortedPlatforms = allPlatforms.toList()..sort();

    return StatefulBuilder(
      builder: (context, setInnerState) {
        final searchQuery = searchController.text.toLowerCase();
        final filteredPlatforms = searchQuery.isEmpty
            ? sortedPlatforms
            : sortedPlatforms.where((p) => p.toLowerCase().contains(searchQuery)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All Platforms (${filteredPlatforms.length})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search platforms...',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (_) => setInnerState(() {}),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredPlatforms.length,
                itemBuilder: (ctx, i) {
                  final slug = filteredPlatforms[i];
                  final compatibleCores = getCoresForSlug(slug);
                  if (compatibleCores.isEmpty) return const SizedBox.shrink();

                  final currentOverride = coreOverrides[slug];
                  final defaultCore = getDefaultCoreForSlug(slug);
                  final currentCoreId = currentOverride ?? defaultCore;
                  final currentCore = compatibleCores.firstWhere(
                    (c) => c.id == currentCoreId,
                    orElse: () => compatibleCores.first,
                  );

                  return _PlatformCoreExpansionTile(
                    slug: slug,
                    compatibleCores: compatibleCores,
                    currentCore: currentCore,
                    currentCoreId: currentCoreId,
                    defaultCore: defaultCore,
                    coreOverrides: coreOverrides,
                    strategyRegistry: strategyRegistry,
                    ref: ref,
                    onOverrideChanged: () => setInnerState(() {}),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
  Widget _buildLinuxSettingsSection(BuildContext context, WidgetRef ref, DirectoryService directoryService) => const SizedBox();

  Widget _buildLegalSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          'Freegosy v${AppConstants.version}',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Freegosy',
            applicationVersion: AppConstants.version,
            applicationIcon: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Image.asset('freegosy_logo.png', height: 64, width: 64),
            ),
          ),
          child: Text('View Licenses', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _showPairingDialog(BuildContext context) {
    final codeController = TextEditingController();
    final theme = Theme.of(context);
    final rommConfig = ref.read(rommConfigProvider).valueOrNull;
    showDialog(
      context: context,
      builder: (context) => DialogBackBridge(
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Pair with Web UI'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the 8-digit code generated in your RomM Web UI settings.'),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                autofocus: true,
                decoration: _buildInputDecoration(context, 'Pairing Code').copyWith(
                  hintText: 'XXXXXXXX',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FocusEffectWrapper(
              onTap: () async {
                final code = codeController.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
                if (code.length < 8) return;
                
                try {
                  final url = _baseUrlController.text.trim();
                  if (url.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a Server URL first.')));
                    return;
                  }
                   final token = await RommService.exchangePairingCode(url, code, trustSelfSigned: rommConfig?.trustSelfSigned ?? false);
                  _apiKeyController.text = token;
                  setState(() => _isLegacyAuth = false);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully paired! Click Save to apply.')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ErrorHandler.showException(context, e, contextLabel: 'Pairing');
                  }
                }
              },
              borderRadius: 12.0,
              scaleFactor: 1.005,
              useSafeScale: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)]),
                ),
                child: Text(
                  'Pair',
                  style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConnectionErrorDetails(BuildContext context, AppError error) {
    final rawLogs = LoggerService().logs.map((e) => e.toString()).join('\n');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raw Logs'),
        content: SingleChildScrollView(
          child: SelectableText(
            rawLogs.isEmpty ? 'No logs available' : rawLogs,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _LogsDialogContent extends StatefulWidget {
  const _LogsDialogContent();

  @override
  State<_LogsDialogContent> createState() => _LogsDialogContentState();
}

class _LogsDialogContentState extends State<_LogsDialogContent> {
  String _filter = 'ALL';
  final ScrollController _scrollController = ScrollController();

  String _maskIPs(String text) {
    final ipRegex = RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b');
    return text.replaceAll(ipRegex, '***.***.***.***');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 800),
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('System Logs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_sweep),
                      onPressed: () => LoggerService().clear(),
                      tooltip: 'Clear Logs',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(label: 'ALL', selected: _filter == 'ALL', onSelected: () => setState(() => _filter = 'ALL')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'SCANNER', selected: _filter == 'SCANNER', onSelected: () => setState(() => _filter = 'SCANNER')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'NETWORK', selected: _filter == 'NETWORK', onSelected: () => setState(() => _filter = 'NETWORK')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'REGISTRY', selected: _filter == 'REGISTRY', onSelected: () => setState(() => _filter = 'REGISTRY')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'DIRECTORY', selected: _filter == 'DIRECTORY', onSelected: () => setState(() => _filter = 'DIRECTORY')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'ERROR', selected: _filter == 'ERROR', onSelected: () => setState(() => _filter = 'ERROR')),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<List<LogEntry>>(
                stream: LoggerService().logStream,
                initialData: LoggerService().logs,
                builder: (context, snapshot) {
                  final allLogs = snapshot.data ?? [];
                  final filteredLogs = allLogs.where((log) {
                    final msg = log.toString().toUpperCase();
                    if (_filter == 'ALL') return true;
                    if (_filter == 'SCANNER') return msg.contains('[SCAN]') || msg.contains('[ROM SCANNER]');
                    if (_filter == 'NETWORK') return msg.contains('[NETWORK]') || msg.contains('[ROMMSERVICE]') || msg.contains('[ROMM-NETWORK]');
                    if (_filter == 'REGISTRY') return msg.contains('[REGISTRY]');
                    if (_filter == 'DIRECTORY') return msg.contains('[DIRECTORYSERVICE]');
                    if (_filter == 'ERROR') return msg.contains('ERROR') || msg.contains('FAILED') || msg.contains('EXCEPTION') || msg.contains(' 404') || msg.contains(' 403') || msg.contains(' 500');
                    return true;
                  }).toList();

                  final fullText = _maskIPs(filteredLogs.map((e) => e.toString()).join('\n'));

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
                    ),
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            fullText,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({required this.label, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusEffectWrapper(
      onTap: onSelected,
      borderRadius: 12.0,
      scaleFactor: 1.005,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected 
              ? theme.colorScheme.primary 
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          border: Border.all(
            color: selected 
                ? theme.colorScheme.primary 
                : theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _PlatformCoreExpansionTile extends StatefulWidget {
  final String slug;
  final List<RetroArchCore> compatibleCores;
  final RetroArchCore currentCore;
  final String? currentCoreId;
  final String? defaultCore;
  final Map<String, String> coreOverrides;
  final StrategyRegistry? strategyRegistry;
  final WidgetRef ref;
  final VoidCallback onOverrideChanged;

  const _PlatformCoreExpansionTile({
    required this.slug,
    required this.compatibleCores,
    required this.currentCore,
    required this.currentCoreId,
    required this.defaultCore,
    required this.coreOverrides,
    required this.strategyRegistry,
    required this.ref,
    required this.onOverrideChanged,
  });

  @override
  State<_PlatformCoreExpansionTile> createState() => _PlatformCoreExpansionTileState();
}

class _PlatformCoreExpansionTileState extends State<_PlatformCoreExpansionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOverride = widget.coreOverrides.containsKey(widget.slug);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: _expanded
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasOverride
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          FocusEffectWrapper(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: 12.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.slug.toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.currentCore.displayName,
                          style: TextStyle(fontSize: 11, color: hasOverride ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (hasOverride)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text('OVR', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    ),
                  const SizedBox(width: 8),
                  Text('${widget.compatibleCores.length} cores', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                children: widget.compatibleCores.map((core) {
                  final isSelected = core.id == widget.currentCoreId;
                  final isFav = widget.ref.watch(retroarchFavoriteCoresProvider).contains(core.id);
                  return FocusEffectWrapper(
                    onTap: () async {
                      if (widget.strategyRegistry != null) {
                        if (core.id == widget.defaultCore) {
                          await widget.strategyRegistry!.clearCoreOverride(widget.slug);
                        } else {
                          await widget.strategyRegistry!.setCoreOverride(widget.slug, core.id);
                        }
                        widget.onOverrideChanged();
                      }
                    },
                    borderRadius: 8.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, size: 16, color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text(core.displayName, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: theme.colorScheme.onSurface)),
                                  if (core.isRecommended) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: Text('REC', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)))],
                                  if (core.id == widget.defaultCore && !isSelected) ...[const SizedBox(width: 6), Text('(default)', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)))],
                                ]),
                                if (core.description != null) Padding(padding: const EdgeInsets.only(top: 1), child: Text(core.description!, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)))),
                              ],
                            ),
                          ),
                          FocusEffectWrapper(
                            onTap: () => widget.ref.read(retroarchFavoriteCoresProvider.notifier).toggle(core.id),
                            borderRadius: 8.0,
                            useSafeScale: false,
                            child: Padding(padding: const EdgeInsets.all(4), child: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4), size: 16)),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
