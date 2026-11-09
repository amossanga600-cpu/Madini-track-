import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_helper.dart';
import 'db_v8.dart';
import 'utils.dart';

/// Karatasi ya ushahidi kwa rekodi moja: picha huhifadhiwa kama FAILI (si blob ndani
/// ya SQLite) na metadata (UUID, checksum, size, status ya upload) kwenye `attachments`.
Future<void> showAttachSheet(
    BuildContext context, String entity, String recordUuid) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AttachSheet(entity: entity, recordUuid: recordUuid),
  );
}

class _AttachSheet extends StatefulWidget {
  final String entity;
  final String recordUuid;
  const _AttachSheet({required this.entity, required this.recordUuid});

  @override
  State<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<_AttachSheet> {
  List<Map<String, dynamic>> _rows = [];
  String _kind = 'Picha';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance
        .getAttachments(recordUuid: widget.recordUuid);
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final x = await ImagePicker()
          .pickImage(source: source, imageQuality: 80, maxWidth: 1600);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'evidence'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = p.extension(x.path).toLowerCase();
      final mime = ext == '.png' ? 'image/png' : 'image/jpeg';
      final path =
          p.join(dir.path, '${newUuid()}${ext.isEmpty ? '.jpg' : ext}');
      await File(path).writeAsBytes(bytes, flush: true);
      await DatabaseHelper.instance.addAttachment(
        recordEntity: widget.entity,
        recordUuid: widget.recordUuid,
        kind: _kind,
        filePath: path,
        mimeType: mime,
        bytes: bytes,
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: [
        Text('Ushahidi', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Aina ya ushahidi'),
          items: [
            for (final k in kEvidenceKinds)
              DropdownMenuItem(value: k, child: Text(k))
          ],
          onChanged: (v) => setState(() => _kind = v ?? 'Picha'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Piga picha'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery'),
            ),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 12),
        if (_rows.isEmpty)
          const Text('Bado hakuna ushahidi kwa rekodi hii.')
        else
          for (final a in _rows)
            ListTile(
              dense: true,
              leading: const Icon(Icons.attach_file),
              title: Text(
                  '${a['kind']} • ${(dbl(a['file_size']) / 1024).round()} KB'),
              subtitle: Text(
                  '${shortDate(a['created_at'])} • ${a['created_by']} • '
                  '${a['upload_status'] == 'uploaded' ? 'Imepakiwa' : 'Inasubiri kupakiwa'}'),
            ),
      ],
    );
  }
}
