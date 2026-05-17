import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../core/storage/directory_service.dart';
import '../../core/storage/system_utils.dart';
import '../../providers/romm_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/shared_prefs_provider.dart';
import '../../providers/downloaded_games_cache_provider.dart';
import '../../core/romm/romm_service.dart';
import '../../core/romm/romm_models.dart';
import '../../core/storage/logger_service.dart';
import 'settings_emulators_section.dart';
import 'settings_display_section.dart';
import 'settings_custom_emulators_section.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/theme_provider.dart';
import '../widgets/focus_effect_wrapper.dart';

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
  bool _isTestingConnection = false;
  String? _connectionError;
  String? _pairedToken;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _apiKeyController = TextEditingController();
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
          builder: (ctx) => AlertDialog(
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
    required Function(bool) onChanged,
  }) {
    final theme = Theme.of(context);
    return FocusEffectWrapper(
      onTap: () => onChanged(!value),
      borderRadius: 16.0,
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
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
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
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
      scaleFactor: 1.03,
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
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  scaleFactor: 1.05,
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
            _preferencesLoaded = true;
          }
          return directoryServiceAsync.when(
            data: (directoryService) {
              if (directoryService == null) return const Center(child: Text('Storage service not available.'));

              return ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildRommServerSection(context, ref, rommService, rommConfig),
                  const SizedBox(height: 20),
                  _buildAppThemeSection(context, ref),
                  const SizedBox(height: 20),
                  _buildSectionCard(
                    context: context,
                    title: 'Library Display',
                    icon: Icons.grid_view,
                    child: buildDisplaySection(context, cardAspectRatio, columnCount, cardSpacing, showTitle, activePreset, ref),
                  ),
                  const SizedBox(height: 20),
                  _buildStorageSection(context, directoryService),
                  const SizedBox(height: 20),
                  _buildRetroArchSettingsSection(context, ref),
                  const SizedBox(height: 20),
                  if (io.Platform.isLinux) ...[
                    _buildLinuxSettingsSection(context, ref, directoryService),
                    const SizedBox(height: 20),
                  ],
                  _buildSectionCard(
                    context: context,
                    title: 'Emulators',
                    icon: Icons.sports_esports,
                    child: emulatorStatusAsync.when(
                      data: (states) => buildEmulatorsSection(context, directoryService, true, states, setState, ref),
                      loading: () => buildEmulatorsSection(context, directoryService, false, {}, setState, ref),
                      error: (e, s) => Center(child: Text('Error: $e')),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionCard(
                    context: context,
                    title: 'Custom Emulators',
                    icon: Icons.settings_input_component,
                    child: const SettingsCustomEmulatorsSection(),
                  ),
                  if (strategyRegistry != null) ...[
                    const SizedBox(height: 20),
                    _buildSectionCard(
                      context: context,
                      title: 'Emulator Conflicts',
                      icon: Icons.warning_amber,
                      child: buildConflictsSection(context, strategyRegistry, setState),
                    ),
                  ],
                  const SizedBox(height: 20),
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

  Widget _buildAppThemeSection(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentTheme = ref.watch(themeProvider);
    return _buildSectionCard(
      context: context,
      title: 'App Theme',
      icon: Icons.palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose the overall visual style of Freegosy.',
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
        ],
      ),
    );
  }

  Widget _buildRommServerSection(BuildContext context, WidgetRef ref, RommService? rommService, RomMConfig rommConfig) {
    final theme = Theme.of(context);
    return _buildSectionCard(
      context: context,
      title: 'RomM Server',
      icon: Icons.dns,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: _baseUrlController, decoration: _buildInputDecoration(context, 'Server URL')),
          const SizedBox(height: 16),
          if (_isLegacyAuth) ...[
            TextField(controller: _usernameController, decoration: _buildInputDecoration(context, 'Username')),
            const SizedBox(height: 16),
            TextField(controller: _passwordController, decoration: _buildInputDecoration(context, 'Password'), obscureText: true),
          ] else
            TextField(controller: _apiKeyController, decoration: _buildInputDecoration(context, 'API Key (RomM 4.8+)'), obscureText: true),
          const SizedBox(height: 16),
          _buildCustomToggleRow(
            context,
            title: 'Legacy Authentication',
            subtitle: 'Enable if your RomM server is below v4.8',
            value: _isLegacyAuth,
            onChanged: (val) => setState(() => _isLegacyAuth = val),
          ),
          const SizedBox(height: 16),
          if (_connectionError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_connectionError!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  context,
                  icon: Icons.phonelink_setup,
                  label: 'Pair Device',
                  onTap: () => _showPairingDialog(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  context,
                  icon: _isTestingConnection ? Icons.hourglass_empty : Icons.network_ping,
                  label: _isTestingConnection ? 'Testing...' : 'Test Connection',
                  onTap: _isTestingConnection ? null : () async {
                    final baseUrl = _baseUrlController.text.trim();
                    if (baseUrl.isEmpty) {
                      setState(() => _connectionError = 'Server URL is required');
                      return;
                    }

                    setState(() {
                      _isTestingConnection = true;
                      _connectionError = null;
                    });

                    try {
                      final testConfig = RomMConfig(
                        baseUrl: baseUrl,
                        username: _usernameController.text.trim(),
                        password: _passwordController.text,
                        apiKey: _pairedToken == null ? _apiKeyController.text.trim() : '',
                        token: _pairedToken,
                      );
                      
                      final testService = RommService(testConfig);
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
                          _connectionError = 'Connection failed: ${e.toString().split('\n').first}';
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
            onTap: () async {
              final prefs = ref.read(sharedPreferencesProvider);
              await prefs.setString('rommBaseUrl', _baseUrlController.text.trim());
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
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
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
          if (io.Platform.isLinux) ...[
            _buildCustomDropdown<String>(
              context: context,
              label: 'Linux App Layout',
              currentValue: preset,
              currentValueLabel: preset == 'default'
                  ? 'Manual / Native'
                  : (preset == 'emudeck' ? 'EmuDeck' : 'RetroDeck'),
              items: const [
                {'value': 'default', 'label': 'Manual / Native'},
                {'value': 'emudeck', 'label': 'EmuDeck'},
                {'value': 'retrodeck', 'label': 'RetroDeck'},
              ],
              onChanged: (val) async {
                await directoryService.setLinuxSyncPreset(val);
                ref.invalidate(directoryServiceProvider);
              },
            ),
            const SizedBox(height: 16),
          ],

          if (io.Platform.isLinux && (preset == 'emudeck' || preset == 'retrodeck')) ...[
            _buildPathRow(
              context,
              label: '${preset == 'emudeck' ? 'EmuDeck' : 'RetroDeck'} Installation Root',
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
          const SizedBox(height: 20),
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
      builder: (context) => const _LogsDialogContent(),
    );
  }

  Widget _buildRetroArchSettingsSection(BuildContext context, WidgetRef ref) => const SizedBox();
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                final token = await RommService.exchangePairingCode(url, code);
                _apiKeyController.text = token;
                setState(() => _isLegacyAuth = false);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully paired! Click Save to apply.')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pairing failed: ${e.toString().split('\n').first}')));
                }
              }
            },
            borderRadius: 12.0,
            scaleFactor: 1.05,
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
      scaleFactor: 1.05,
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
