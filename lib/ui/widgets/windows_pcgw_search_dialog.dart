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

class WindowsPcgwDialog extends StatefulWidget {
  final List<String> results;


  const WindowsPcgwDialog({
    super.key,
    required this.results,
  });

  @override
  State<WindowsPcgwDialog> createState() => _WindowsPcgwDialogState();
}

class _WindowsPcgwDialogState extends State<WindowsPcgwDialog> {
  late List<String> _results;

  @override
  void initState() {
    super.initState();
    _results = widget.results;
  }

  @override
  void dispose() {
    super.dispose();
    _results.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog (
      title: Text('Search Results'),
      content: SingleChildScrollView (

      child: SizedBox.square (
        dimension: 350,
        child: Scrollbar(
          thumbVisibility: true,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _results.length,
          itemBuilder: (BuildContext context, int index) {
            return TextButton (
              onPressed: () => Navigator.of(context).pop({
                  'results': _results.elementAt(index),
                }),
              child: Align (
                alignment: Alignment.centerLeft, 
                child: Text(_results.elementAt(index), overflow: TextOverflow.fade, textAlign: TextAlign.left, softWrap: true),
              ),
            );
          },
          separatorBuilder: (BuildContext context, int index) {
            return const SizedBox(height: 4);
          },
      ),
      ),
      ),
       ),
    );
  }
}