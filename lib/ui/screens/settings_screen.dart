import 'dart:io' as io;
import 'package:flutter/foundation.dart';
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
  bool _connectionSuccess = false;

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
            Image.asset('freegosy_logo.png', height: 32, width: 32),
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
                  const SizedBox(height: 24),
                  buildDisplaySection(context, cardAspectRatio, columnCount, cardSpacing, showTitle, activePreset, ref),
                  const SizedBox(height: 24),
                  _buildStorageSection(directoryService),
                  const SizedBox(height: 24),
                  _buildRetroArchSettingsSection(context, ref),
                  const SizedBox(height: 24),
                  if (defaultTargetPlatform == TargetPlatform.linux) ...[
                    _buildLinuxSettingsSection(context, ref, directoryService),
                    const SizedBox(height: 24),
                  ],
                  emulatorStatusAsync.when(
                    data: (states) => buildEmulatorsSection(context, directoryService, true, states, setState, ref),
                    loading: () => buildEmulatorsSection(context, directoryService, false, {}, setState, ref),
                    error: (e, s) => Center(child: Text('Error: $e')),
                  ),
                  const SizedBox(height: 24),
                  const SettingsCustomEmulatorsSection(),
                  if (strategyRegistry != null) ...[
                    const SizedBox(height: 24),
                    buildConflictsSection(strategyRegistry, setState),
                  ],
                  const SizedBox(height: 24),
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

  // --- RomM Server Section (Kept as is) ---
  Widget _buildRommServerSection(BuildContext context, WidgetRef ref, RommService? rommService, RomMConfig rommConfig) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('RomM Server', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      TextField(controller: _baseUrlController, decoration: const InputDecoration(labelText: 'Server URL', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      if (_isLegacyAuth) ...[
        TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
      ] else
        TextField(controller: _apiKeyController, decoration: const InputDecoration(labelText: 'API Key (RomM 4.8+)', border: OutlineInputBorder()), obscureText: true),
      const SizedBox(height: 16),
      Row(children: [
        const Text('Legacy Authentication'),
        const Spacer(),
        Switch(value: _isLegacyAuth, onChanged: (val) => setState(() => _isLegacyAuth = val)),
      ]),
      const SizedBox(height: 16),
      const SizedBox(height: 16),
      if (_connectionError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(_connectionError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ),
      if (_connectionSuccess)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Connection successful!', style: TextStyle(color: Colors.green, fontSize: 13)),
        ),
      Row(
        children: [
          ElevatedButton(
            onPressed: _isTestingConnection ? null : () async {
              final baseUrl = _baseUrlController.text.trim();
              if (baseUrl.isEmpty) {
                setState(() => _connectionError = 'Server URL is required');
                return;
              }

              setState(() {
                _isTestingConnection = true;
                _connectionError = null;
                _connectionSuccess = false;
              });

              try {
                // Temporary config for testing
                final testConfig = RomMConfig(
                  baseUrl: baseUrl,
                  username: _usernameController.text.trim(),
                  password: _passwordController.text,
                  apiKey: _apiKeyController.text.trim(),
                );
                
                final testService = RommService(testConfig);
                await testService.getPlatforms(); // Simple connectivity test
                
                if (mounted) {
                  setState(() {
                    _isTestingConnection = false;
                    _connectionSuccess = true;
                  });
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
            child: _isTestingConnection 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Test Connection'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final prefs = ref.read(sharedPreferencesProvider);
              await prefs.setString('rommBaseUrl', _baseUrlController.text.trim());
              if (_isLegacyAuth) {
                 await prefs.setString('rommUsername', _usernameController.text.trim());
                 await SecureStorageService.write('rommPassword', _passwordController.text, prefs);
              } else {
                 await SecureStorageService.write('rommApiKey', _apiKeyController.text.trim(), prefs);
              }
              ref.invalidate(rommConfigProvider);
              ref.invalidate(rommServiceProvider);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ]);
  }

  // --- Storage Section ---
  Widget _buildStorageSection(DirectoryService directoryService) {
    final prefs = ref.read(sharedPreferencesProvider);
    final preset = directoryService.linuxSyncPreset;
    
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Storage', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      
      if (io.Platform.isLinux) ...[
        const Text('Linux App Layout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(preset),
          initialValue: preset,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'default', child: Text('Manual / Native')),
            DropdownMenuItem(value: 'emudeck', child: Text('EmuDeck')),
            DropdownMenuItem(value: 'retrodeck', child: Text('RetroDeck')),
          ],
          onChanged: (val) async {
            if (val != null) {
              await directoryService.setLinuxSyncPreset(val);
              ref.invalidate(directoryServiceProvider);
            }
          },
        ),
        const SizedBox(height: 16),
      ],

      if (io.Platform.isLinux && (preset == 'emudeck' || preset == 'retrodeck')) ...[
        _buildPathRow(
          label: '${preset == 'emudeck' ? 'EmuDeck' : 'RetroDeck'} Installation Root',
          currentPath: preset == 'emudeck' 
              ? (directoryService.emudeckRootPath ?? 'Not set') 
              : (prefs.getString('retrodeckRootPath') ?? 'Not set'),
          onChanged: (p) async { 
            if (p != null) { 
              if (preset == 'emudeck') {
                await directoryService.setEmudeckRoot(p);
              } else {
                await prefs.setString('retrodeckRootPath', p);
                await directoryService.initialize();
              }
              ref.invalidate(directoryServiceProvider); 
            } 
          },
        ),
        const SizedBox(height: 16),
        const Text('Computed Paths (Read-only)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        _buildPathRow(
          label: 'ROMs Directory',
          currentPath: directoryService.romsRootPath,
          onChanged: null,
        ),
        const SizedBox(height: 12),
        _buildPathRow(
          label: 'Emulators Directory',
          currentPath: directoryService.emulatorsRootPath,
          onChanged: null,
        ),
      ] else ...[
        // This handles both non-Linux OSs and Linux 'Manual' mode
        _buildPathRow(
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
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => SystemUtils.openDirectory(directoryService.romsRootPath),
        icon: const Icon(Icons.folder_open),
        label: const Text('Open ROMs Directory'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: SystemUtils.openAppDataDirectory,
        icon: const Icon(Icons.folder_open),
        label: const Text('Open App Data Directory'),
      ),
      const SizedBox(height: 16),
      const Divider(color: Colors.white10),
      const SizedBox(height: 8),
      const Text('Troubleshooting', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      const Text('If games are missing from your offline library, try a full scan.', style: TextStyle(color: Colors.white54, fontSize: 13)),
      const SizedBox(height: 12),
      Consumer(builder: (context, ref, _) {
        final isScanning = ref.watch(isScanningProvider);
        return OutlinedButton.icon(
          onPressed: isScanning ? null : () async {
            await ref.read(downloadedGamesCacheProvider.notifier).startIncrementalSync(force: true);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full ROM scan complete.')));
            }
          },
          icon: isScanning 
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sync),
          label: Text(isScanning ? 'Scanning...' : 'Force Full ROM Scan'),
        );
      }),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => _showLogsDialog(context),
        icon: const Icon(Icons.receipt_long),
        label: const Text('View Console Logs'),
      ),
    ]);
  }

  void _showLogsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: double.infinity,
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
              const Divider(),
              Expanded(
                child: StreamBuilder<List<LogEntry>>(
                  stream: LoggerService().logStream,
                  initialData: LoggerService().logs,
                  builder: (context, snapshot) {
                    final logs = snapshot.data ?? [];
                    return ListView.builder(
                      reverse: true,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[logs.length - 1 - index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            log.toString(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPathRow({required String label, required String currentPath, required Function(String?)? onChanged, VoidCallback? onReset}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      Row(children: [
        Expanded(child: Text(currentPath, overflow: TextOverflow.ellipsis)),
        if (onReset != null) IconButton(onPressed: onReset, icon: const Icon(Icons.restore)),
        if (onChanged != null) ElevatedButton(onPressed: () async => onChanged(await FilePicker.platform.getDirectoryPath()), child: const Text('Change')),
      ]),
    ]);
  }

  // --- Placeholder methods for sections to pass analysis ---
  Widget _buildRetroArchSettingsSection(BuildContext context, WidgetRef ref) => const SizedBox();
  Widget _buildLinuxSettingsSection(BuildContext context, WidgetRef ref, DirectoryService directoryService) => const SizedBox();
  Widget _buildLegalSection(BuildContext context) => const SizedBox();
}
