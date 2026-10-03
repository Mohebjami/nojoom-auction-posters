import 'package:flutter/material.dart';

import 'batch_export_delivery.dart';
import 'batch_poster_export.dart';
import 'poster_history.dart';
import 'studio_ui.dart';
import 'vehicle_number_sort.dart';

typedef BatchPosterGenerator =
    Future<BatchPosterExport> Function({
      required PosterHistory history,
      required List<int> ids,
      required BatchPosterFormat format,
      void Function(int completed, int total)? onProgress,
      bool Function()? isCancelled,
    });

typedef BatchPosterSaver =
    Future<String?> Function(
      BatchPosterExport export, {
      required Rect sharePositionOrigin,
    });

class BatchPostersScreen extends StatefulWidget {
  final PosterHistory history;
  // History supplies its filtered, sorted collection; Create loads all drafts.
  final List<PosterHistoryEntry>? entries;
  final BatchPosterGenerator generate;
  final BatchPosterSaver saveExport;

  const BatchPostersScreen({
    super.key,
    required this.history,
    this.entries,
    this.generate = generateBatchPosters,
    this.saveExport = saveBatchPosterExport,
  });

  @override
  State<BatchPostersScreen> createState() => _BatchPostersScreenState();
}

class _BatchPostersScreenState extends State<BatchPostersScreen> {
  List<PosterHistoryEntry>? _entries;
  final Set<int> _selected = {};
  String? _error;
  String? _message;
  bool _busy = false;
  bool _saving = false;
  bool _cancelled = false;
  int _completed = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _entries = null;
    });
    try {
      final entries = widget.entries?.toList() ?? await widget.history.list();
      if (widget.entries == null) {
        entries.sort((a, b) {
          final order = compareVehicleNumbers(
            a.vehicle.number,
            b.vehicle.number,
          );
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _selected
          ..clear()
          ..addAll(entries.map((entry) => entry.id));
      });
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Could not load saved posters: $error');
    }
  }

  Future<void> _export(BatchPosterFormat format) async {
    if (_busy || _selected.isEmpty) return;
    final ids = _entries!
        .where((entry) => _selected.contains(entry.id))
        .map((entry) => entry.id)
        .toList();
    setState(() {
      _busy = true;
      _cancelled = false;
      _completed = 0;
      _total = ids.length;
      _error = null;
      _message = null;
    });
    try {
      final result = await widget.generate(
        history: widget.history,
        ids: ids,
        format: format,
        isCancelled: () => _cancelled || !mounted,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() {
              _completed = completed;
              _total = total;
            });
          }
        },
      );
      if (!mounted || _cancelled) return;
      setState(() => _saving = true);
      final box = context.findRenderObject();
      final origin = box is RenderBox
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);
      final message = await widget.saveExport(
        result,
        sharePositionOrigin: origin,
      );
      if (mounted) setState(() => _message = message ?? 'Export cancelled.');
    } catch (error) {
      if (mounted && !_cancelled) {
        setState(() => _error = 'Could not generate posters: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          if (_cancelled)
            _message = 'Generation cancelled. No file was exported.';
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  void _cancel() => setState(() => _cancelled = true);

  Widget _status() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: _total == 0 ? null : _completed / _total,
        ),
        const SizedBox(height: 8),
        Text(
          _saving
              ? 'Saving export…'
              : _cancelled
              ? 'Cancelling…'
              : _completed == _total
              ? 'Preparing your download…'
              : 'Generating poster ${_completed + 1} of $_total…',
        ),
      ],
    ),
  );

  Widget _list() {
    final entries = _entries;
    if (entries == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
      );
    }
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No saved posters yet.\nAdd photos and save a draft for each vehicle, then return here to generate them all.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        CheckboxListTile(
          title: const Text('Select all'),
          subtitle: Text('${_selected.length} of ${entries.length} selected'),
          value: _selected.length == entries.length
              ? true
              : _selected.isEmpty
              ? false
              : null,
          tristate: true,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: _busy
              ? null
              : (_) => setState(() {
                  if (_selected.length == entries.length) {
                    _selected.clear();
                  } else {
                    _selected.addAll(entries.map((entry) => entry.id));
                  }
                }),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final number = entry.vehicle.number.trim();
              final vin = entry.vehicle.vin.trim();
              return CheckboxListTile(
                key: ValueKey('batch-poster-${entry.id}'),
                title: Text(
                  number.isEmpty ? entry.title : 'No. $number · ${entry.title}',
                ),
                subtitle: vin.isEmpty ? null : Text(vin),
                value: _selected.contains(entry.id),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: _busy
                    ? null
                    : (selected) => setState(() {
                        if (selected == true) {
                          _selected.add(entry.id);
                        } else {
                          _selected.remove(entry.id);
                        }
                      }),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Generate all posters'),
        leading: BackButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Text(
                    'Choose your saved vehicles. Each poster uses its saved photos, details, and template.\n'
                    'Download separate JPGs in a ZIP, or create one PDF with a complete poster on each page.',
                    style: TextStyle(color: StudioColors.muted, height: 1.5),
                  ),
                ),
                Expanded(child: _list()),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: StudioColors.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null || _message != null) ...[
                        Text(
                          _error ?? _message!,
                          key: const ValueKey('batch-export-message'),
                          style: TextStyle(
                            color: _error == null
                                ? StudioColors.ink
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_busy) ...[
                        _status(),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _saving || _cancelled ? null : _cancel,
                            child: const Text('Cancel generation'),
                          ),
                        ),
                      ] else
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _selected.isEmpty
                                  ? null
                                  : () => _export(BatchPosterFormat.jpgZip),
                              icon: const Icon(Icons.folder_zip_outlined),
                              label: const Text('Separate JPGs (ZIP)'),
                            ),
                            FilledButton.icon(
                              onPressed: _selected.isEmpty
                                  ? null
                                  : () => _export(BatchPosterFormat.pdf),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Create PDF'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
