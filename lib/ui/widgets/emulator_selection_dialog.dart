import 'package:flutter/material.dart';

class EmulatorSelectionDialog extends StatelessWidget {
  final List<Map<String, String>> assets;
  final Function(String) onSelect;

  const EmulatorSelectionDialog({
    super.key,
    required this.assets,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Emulator Version'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: assets.length,
          itemBuilder: (context, index) {
            final asset = assets[index];
            return ListTile(
              title: Text(asset['name'] ?? 'Unknown Version'),
              onTap: () {
                final url = asset['url'];
                if (url != null) {
                  onSelect(url);
                  Navigator.of(context).pop();
                }
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
