import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../providers/romm_provider.dart';
import '../../providers/shared_prefs_provider.dart';
import '../../core/romm/romm_service.dart';
import '../../core/romm/romm_models.dart';
import '../../core/storage/secure_storage_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 4;

  // Step 1: Server Config
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isTesting = false;
  String? _testError;
  bool _testSuccess = false;

  // Step 2: Storage Config
  String? _romsRoot;
  String? _emusRoot;
  String _linuxPreset = 'default';
  bool _isStorageInitialized = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController.text = 'http://';
    _loadExistingConfig();
  }

  Future<void> _loadExistingConfig() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final baseUrl = prefs.getString('rommBaseUrl') ?? '';
    final apiKey = await SecureStorageService.read('rommApiKey', prefs) ?? '';
    final romsRoot = prefs.getString('romsRootPath');
    final emusRoot = prefs.getString('emulatorsRootPath');
    final linuxPreset = prefs.getString('linuxSyncPreset') ?? 'default';

    if (!mounted) return;

    setState(() {
      if (baseUrl.isNotEmpty && baseUrl != 'http://') {
        _baseUrlController.text = baseUrl;
      }
      _apiKeyController.text = apiKey;
      if (romsRoot != null) _romsRoot = romsRoot;
      if (emusRoot != null) _emusRoot = emusRoot;
      _linuxPreset = linuxPreset;
      if (romsRoot != null || emusRoot != null) {
        _isStorageInitialized = true;
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final url = _baseUrlController.text.trim();
    if (url.isEmpty || url == 'http://' || url == 'https://') {
      setState(() => _testError = 'Please enter a valid Server URL');
      return;
    }

    setState(() {
      _isTesting = true;
      _testError = null;
      _testSuccess = false;
    });

    try {
      final testConfig = RomMConfig(
        baseUrl: url,
        apiKey: _apiKeyController.text.trim(),
        username: '',
        password: '',
      );
      final testService = RommService(testConfig);
      await testService.getPlatforms(); // Quick check
      
      setState(() {
        _isTesting = false;
        _testSuccess = true;
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testError = 'Connection failed: ${e.toString().split('\n').first}';
      });
    }
  }

  Future<void> _initializeDefaultStorage() async {
    if (_isStorageInitialized) return;
    final dirService = await ref.read(directoryServiceProvider.future);
    if (dirService != null) {
      setState(() {
        _romsRoot = dirService.romsRootPath;
        _emusRoot = dirService.emulatorsRootPath;
        _isStorageInitialized = true;
      });
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = ref.read(sharedPreferencesProvider);
    
    // Save RomM Config
    await prefs.setString('rommBaseUrl', _baseUrlController.text.trim());
    await SecureStorageService.write('rommApiKey', _apiKeyController.text.trim(), prefs);
    
    // Save Storage Config
    if (_romsRoot != null) await prefs.setString('romsRootPath', _romsRoot!);
    if (_emusRoot != null) await prefs.setString('emulatorsRootPath', _emusRoot!);
    
    if (io.Platform.isLinux) {
      await prefs.setString('linuxSyncPreset', _linuxPreset);
    }

    // Invalidate providers to trigger reload
    ref.invalidate(rommConfigProvider);
    ref.invalidate(rommServiceProvider);
    ref.invalidate(directoryServiceProvider);
  }

  void _nextPage() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
      
      if (_currentStep == 2) {
        _initializeDefaultStorage();
      }
    } else {
      _finishOnboarding();
    }
  }

  void _prevPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f0f),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.5,
            colors: [
              Colors.deepPurple.withValues(alpha: 0.15),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomeStep(),
                  _buildServerStep(),
                  _buildStorageStep(),
                  _buildFinishStep(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Hero(
            tag: 'logo',
            child: Image.asset('freegosy_logo.png', height: 120),
          ),
          const SizedBox(height: 48),
          const Text(
            'Welcome to Freegosy',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'The ultimate open-source cross-platform launcher for your self-hosted RomM library.',
            style: TextStyle(fontSize: 18, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          _buildInfoCard(
            icon: Icons.cloud_sync,
            title: 'Cloud Save Sync',
            subtitle: 'Sync your game saves across Windows, Linux, and macOS.',
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.download_for_offline,
            title: 'Automated Downloads',
            subtitle: 'Fetch emulators and ROMs with a single click.',
          ),
        ],
      ),
    );
  }

  Widget _buildServerStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect to RomM',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your RomM server details to browse your library.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://your-ip:8080',
              prefixIcon: Icon(Icons.dns),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'Found in RomM User Settings',
              prefixIcon: Icon(Icons.key),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 32),
          if (_testError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_testError!, style: const TextStyle(color: Colors.red))),
                ],
              ),
            ),
          if (_testSuccess)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green),
                  SizedBox(width: 12),
                  Text('Connection Successful!', style: TextStyle(color: Colors.green)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isTesting ? null : _testConnection,
              child: _isTesting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Test Connection'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Storage Setup',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Where should we store your games and emulators?',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),
          
          if (io.Platform.isLinux) ...[
            const Text('Platform Preset', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildPresetOption(
              id: 'default',
              title: 'Manual / Native',
              subtitle: 'Custom paths for everything.',
              icon: Icons.folder,
            ),
            const SizedBox(height: 12),
            _buildPresetOption(
              id: 'emudeck',
              title: 'EmuDeck',
              subtitle: 'Standard Steam Deck layout.',
              icon: Icons.sports_esports,
            ),
            const SizedBox(height: 12),
            _buildPresetOption(
              id: 'retrodeck',
              title: 'RetroDeck',
              subtitle: 'Flatpak-based all-in-one.',
              icon: Icons.grid_view,
            ),
            const SizedBox(height: 32),
          ],

          _buildPathSelector(
            label: 'ROMs Directory',
            currentPath: _romsRoot ?? 'Loading...',
            onTap: () async {
              final path = await FilePicker.platform.getDirectoryPath();
              if (path != null) setState(() => _romsRoot = path);
            },
          ),
          const SizedBox(height: 24),
          _buildPathSelector(
            label: 'Emulators Directory',
            currentPath: _emusRoot ?? 'Loading...',
            onTap: () async {
              final path = await FilePicker.platform.getDirectoryPath();
              if (path != null) setState(() => _emusRoot = path);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFinishStep() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.rocket_launch, size: 80, color: Colors.deepPurple),
          const SizedBox(height: 32),
          const Text(
            "You're all set!",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Freegosy is ready to manage your library. You can always change these settings later.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                _buildSummaryRow('Server', _baseUrlController.text),
                const Divider(height: 24),
                _buildSummaryRow('ROMs', p.basename(_romsRoot ?? '')),
                const Divider(height: 24),
                _buildSummaryRow('Emulators', p.basename(_emusRoot ?? '')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: _prevPage,
              child: const Text('Back'),
            )
          else
            const SizedBox.shrink(),
          
          Row(
            children: List.generate(_totalSteps, (index) {
              return Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentStep == index 
                      ? Colors.deepPurple 
                      : Colors.grey.withValues(alpha: 0.3),
                ),
              );
            }),
          ),

          ElevatedButton(
            onPressed: (_currentStep == 1 && !_testSuccess) ? null : _nextPage,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_currentStep == _totalSteps - 1 ? 'Get Started' : 'Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: Colors.deepPurple),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathSelector({required String label, required String currentPath, required VoidCallback onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_open, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(child: Text(currentPath, overflow: TextOverflow.ellipsis)),
                const Icon(Icons.edit, size: 16, color: Colors.deepPurple),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetOption({required String id, required String title, required String subtitle, required IconData icon}) {
    final isSelected = _linuxPreset == id;
    return InkWell(
      onTap: () => setState(() => _linuxPreset = id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurple.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.deepPurple : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.deepPurple : Colors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: Colors.deepPurple),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
