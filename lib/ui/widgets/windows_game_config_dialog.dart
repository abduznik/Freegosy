import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/romm/romm_models.dart';

class WindowsGameConfigDialog extends StatefulWidget {
  final Game game;
  final String? currentExePath;
  final String? currentSavePath;
  final String? currentLaunchArgs;

  const WindowsGameConfigDialog({
    super.key,
    required this.game,
    this.currentExePath,
    this.currentSavePath,
    this.currentLaunchArgs,
  });

  @override
  State<WindowsGameConfigDialog> createState() => _WindowsGameConfigDialogState();
}

class _WindowsGameConfigDialogState extends State<WindowsGameConfigDialog> {
  late TextEditingController _exeController;
  late TextEditingController _saveController;
  late TextEditingController _argsController;

  @override
  void initState() {
    super.initState();
    _exeController = TextEditingController(text: widget.currentExePath ?? '');
    _saveController = TextEditingController(text: widget.currentSavePath ?? '');
    _argsController = TextEditingController(text: widget.currentLaunchArgs ?? '');
  }

  @override
  void dispose() {
    _exeController.dispose();
    _saveController.dispose();
    _argsController.dispose();
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
              'Save Directory',
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
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
