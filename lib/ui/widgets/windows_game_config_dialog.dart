import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freegosy/providers/romm_provider.dart';
import '../../core/romm/romm_models.dart';
import '../../core/windows/pcgamingwiki_service.dart';
import 'package:dio/dio.dart';
import '../../core/storage/system_utils.dart';
import '../../core/storage/directory_service.dart';
import '../../core/storage/app_preferences.dart';

class WindowsGameConfigDialog extends StatefulWidget {
  final Game game;
  final DirectoryService? directoryService;
  final String? manualWikiSearch;
  final String? currentExePath;
  final String? currentSavePath;
  final String? currentLaunchArgs;
  final String? currentSaveFilter;
  final String? currentWikiSavePath;
  final String? currentWikiFileFilter;

  const WindowsGameConfigDialog({
    super.key,
    required this.game,
    this.directoryService,
    this.manualWikiSearch,
    this.currentExePath,
    this.currentSavePath,
    this.currentLaunchArgs,
    this.currentSaveFilter,
    this.currentWikiSavePath,
    this.currentWikiFileFilter,
  });

  @override
  State<WindowsGameConfigDialog> createState() => _WindowsGameConfigDialogState();
}

class _WindowsGameConfigDialogState extends State<WindowsGameConfigDialog> {
  late TextEditingController _manualWikiSearchController;
  late TextEditingController _exeController;
  late TextEditingController _saveController;
  late TextEditingController _argsController;
  late TextEditingController _filterController;
  late TextEditingController _wikiSavePathController;
  late TextEditingController _wikiFileFilterController;

  late bool _triedAutoDetect;

  @override
  void initState() {
    super.initState();
    _manualWikiSearchController = TextEditingController(text: widget.manualWikiSearch ?? '');
    _exeController = TextEditingController(text: widget.currentExePath ?? '');
    _saveController = TextEditingController(text: widget.currentSavePath ?? '');
    _argsController = TextEditingController(text: widget.currentLaunchArgs ?? '');
    _filterController = TextEditingController(text: widget.currentSaveFilter ?? '');
    _wikiSavePathController = TextEditingController(text: widget.currentWikiSavePath ?? '');
    _wikiFileFilterController = TextEditingController(text: widget.currentWikiFileFilter ?? '');

    _triedAutoDetect = false;
  }

  @override
  void dispose() {
    _manualWikiSearchController.dispose();
    _exeController.dispose();
    _saveController.dispose();
    _argsController.dispose();
    _filterController.dispose();
    _wikiSavePathController.dispose();
    _wikiFileFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Configure ${widget.game.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Executable',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              '.exe, .bat, or .cmd files supported',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _exeController,
                    decoration: const InputDecoration(
                      hintText: 'Auto-detect or browse...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['exe', 'bat', 'cmd'],
                    );
                    if (result != null && result.files.single.path != null) {
                      setState(() {
                        _exeController.text = result.files.single.path!;
                      });
                    }
                  },
                  child: const Text('Browse'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Launch Arguments',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Arguments passed to the executable on launch',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _argsController,
              decoration: const InputDecoration(
                hintText: 'e.g. --windowed --res 1920x1080',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Save Directory - Manual Override',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Leave empty to use PCGamingWiki auto-detection',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _saveController,
                    decoration: const InputDecoration(
                      hintText: 'Auto-detect or browse...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final path = await FilePicker.platform.getDirectoryPath();
                    if (path != null) {
                      setState(() {
                        _saveController.text = path;
                      });
                    }
                  },
                  child: const Text('Browse'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Save File Filter - Manual Override',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select which files to back up. Leave empty to sync the entire folder.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _filterController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. *.ini, *.bin, eeprom.*',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      allowMultiple: true,
                      type: FileType.any,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      final names = result.files
                          .where((f) => f.name.isNotEmpty)
                          .map((f) => f.name)
                          .join(', ');
                      setState(() {
                        if (_filterController.text.isNotEmpty) {
                          _filterController.text = '${_filterController.text}, $names';
                        } else {
                          _filterController.text = names;
                        }
                      });
                    }
                  },
                  child: const Text('Browse'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'PCGamingWiki Save Directory Auto-detection',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              "Save path and file filter (if any) will be resolved using PCGW.\nManual overrides will always take priority over these.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualWikiSearchController,
                    decoration: InputDecoration(
                      hintText: widget.game.name,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                  )
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final PcGamingWikiService wikiService = PcGamingWikiService(Dio());
                    final existingGameDir = await widget.directoryService!.findExistingRomPath(widget.game);
                    final locations = await wikiService.getSaveLocations(_manualWikiSearchController.text.isEmpty ? widget.game.name : _manualWikiSearchController.text, gameDir: existingGameDir!);
                    if (locations.isNotEmpty) {
                      for (final loc in locations) {
                        debugPrint('[WindowsSave]   raw: ${loc['raw']} → path: ${loc['path']}');
                      }
                      final resolved = locations.first['path'];
                      final resolvedFileFilter = locations.first['raw']!.split('\\').last;
                      if (resolved != null) {
                        final names = resolved;
                        setState(() {
                          _triedAutoDetect = true;
                          _wikiSavePathController.text = names;
                          if (resolvedFileFilter.isNotEmpty) _wikiFileFilterController.text = resolvedFileFilter;
                        });
                      }
                    } else if (_wikiSavePathController.text.isEmpty) {
                      setState(() {
                        _triedAutoDetect = true;
                      });
                    }
                  },
                  child: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_triedAutoDetect && _wikiSavePathController.text.isEmpty) RichText (
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
                children: <TextSpan>[
                  TextSpan(text: 'Nothing found.', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '\nTry a different wording, or enter directly the PCGW Page Title.'),
                ],
              ),
            ),
            Row(
              children: [
                if (_wikiSavePathController.text.isNotEmpty) ElevatedButton(
                  onPressed: () async {
                    final folder = _wikiSavePathController.text;
                    if (folder.isNotEmpty) await SystemUtils.openDirectory(folder);
                  },
                  child: const Text('Open Folder'),
                ),
                const SizedBox(width: 8),
                if (_wikiSavePathController.text.isNotEmpty) ElevatedButton(
                  onPressed: () async {
                    setState(() {
                    _wikiSavePathController.text = '';
                    });
                  },
                  child: const Text('Clear'),
                ),
              ]
            ),
            const SizedBox (height: 8),
            if (_wikiSavePathController.text.isNotEmpty) RichText (
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                 ),
                 children: <TextSpan>[
                  TextSpan(text:'Path Found :', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text:'\n"${_wikiSavePathController.text}"\n'),
                  TextSpan(text: _wikiFileFilterController.text.isNotEmpty ? '\nFile Filter (Include):' : '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: _wikiFileFilterController.text.isNotEmpty ? '\n${_wikiFileFilterController.text}' : ''),
                 ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop({
            'exe': _exeController.text.trim(),
            'save': _saveController.text.trim(),
            'args': _argsController.text.trim(),
            'filter': _filterController.text.trim(),
            'wikiSavePath': _wikiSavePathController.text.trim(),
            'wikiFilter': _wikiFileFilterController.text.trim(),
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
