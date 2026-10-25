import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'backup_delivery.dart';
import 'poster_backup.dart';
import 'poster_history.dart';
import 'studio_ui.dart';

class BackupScreen extends StatefulWidget {
  final PosterHistory history;
  final VoidCallback onImported;

  const BackupScreen({
    super.key,
    required this.history,
    required this.onImported,
  });

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  bool _confirming = false;
  String? _status;
  bool _failed = false;

  Future<void> _export() async {
    if (_busy) return;
    // Capture the share anchor before asynchronous work changes the layout.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    _start('Preparing backup, including all saved images…');
    try {
      final bytes = await widget.history.exportBackup();
      if (!mounted) return;
      final message = await savePosterBackup(
        bytes,
        sharePositionOrigin: origin,
      );
      if (mounted) setState(() => _status = message);
    } catch (error) {
      _error('Could not export backup: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    _start('Choose a backup ZIP to import.');
    try {
      final file = await openFile(acceptedTypeGroups: [backupFileType]);
      if (file == null) {
        if (mounted) setState(() => _status = null);
        return;
      }
      if (mounted) setState(() => _status = 'Checking backup and images…');
      final backup = await compute(
        PosterBackup.decode,
        await file.readAsBytes(),
      );
      if (!mounted) return;
      setState(() {
        _confirming = true;
        _status = null;
      });
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StudioConfirmDialog(
          title: 'Import this backup?',
          message:
              'This backup contains ${backup.posters.length} saved posters, '
              '${backup.photoCount} images and '
              '${backup.auctionVehicles.length} auction vehicles.\n\n'
              'These will be added as copies. Existing data will be kept. '
              'Importing the same backup again creates more copies.',
          cancelLabel: 'Cancel',
          confirmLabel: 'Import backup',
          icon: Icons.restore_rounded,
          confirmIcon: Icons.file_download_outlined,
        ),
      );
      if (mounted) setState(() => _confirming = false);
      if (confirmed != true || !mounted) {
        if (mounted) setState(() => _status = null);
        return;
      }
      setState(() => _status = 'Importing backup and images…');
      await widget.history.importBackup(backup);
      if (!mounted) return;
      widget.onImported();
      setState(() {
        _status =
            'Imported ${backup.posters.length} posters, '
            '${backup.photoCount} images and '
            '${backup.auctionVehicles.length} auction vehicles.';
      });
    } catch (error) {
      _error('Could not import backup: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  void _start(String message) => setState(() {
    _busy = true;
    _failed = false;
    _status = message;
  });

  void _error(String message) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _status = message;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: StudioColors.paper,
      appBar: AppBar(
        title: const Text('Backup and restore'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: StudioCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.backup_outlined,
                    size: 42,
                    color: StudioColors.accent,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Take your workspace with you.',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Export all saved posters, original images, custom templates, '
                    'vehicle details, dates and the full auction list in one ZIP. '
                    'Save your latest edits before making a backup.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Copy the ZIP to your other device or app version, then open '
                    'History → Backup and restore → Import backup. The receiving '
                    'version must support backups.',
                    style: TextStyle(color: StudioColors.muted),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const ValueKey('export-backup'),
                    onPressed: _busy ? null : _export,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Export backup'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('import-backup'),
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Import backup'),
                  ),
                  if (_busy && !_confirming) ...[
                    const SizedBox(height: 20),
                    const LinearProgressIndicator(),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _status!,
                      key: const ValueKey('backup-status'),
                      style: TextStyle(
                        color: _failed ? Colors.red.shade700 : StudioColors.ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
