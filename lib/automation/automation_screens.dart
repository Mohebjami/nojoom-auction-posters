import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../duplicate_vehicle_dialog.dart';
import '../poster_history.dart';
import '../studio_ui.dart';
import '../vehicle_draft_import.dart';
import '../vehicle_import.dart';
import 'automation_client.dart';
import 'photo_attachment.dart';

List<Map<String, dynamic>> _rows(Object? value) => [
  for (final row in value as List? ?? []) Map<String, dynamic>.from(row as Map),
];

class AutomationPanel extends StatelessWidget {
  const AutomationPanel({super.key, required this.client, required this.child});
  final AutomationClient client;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!client.supported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Photo Finder and NCA Import are available in the combined '
            'Nojoom Mac app. Poster creation, auction lists, labels and history '
            'remain available here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!client.connected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (client.connecting) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                client.error ?? 'Starting Nojoom automation…',
                textAlign: TextAlign.center,
              ),
              if (!client.connecting)
                TextButton(
                  onPressed: client.start,
                  child: const Text('Start automation'),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        if (client.error != null)
          MaterialBanner(
            content: Text(client.error!),
            actions: [
              TextButton(
                onPressed: client.start,
                child: const Text('Reconnect'),
              ),
            ],
          ),
        Expanded(child: child),
      ],
    );
  }
}

class PhotoFinderScreen extends StatefulWidget {
  const PhotoFinderScreen({
    super.key,
    required this.client,
    required this.history,
    required this.onLibraryChanged,
    this.refreshSignal,
  });
  final AutomationClient client;
  final PosterHistory history;
  final VoidCallback onLibraryChanged;
  final Listenable? refreshSignal;
  @override
  State<PhotoFinderScreen> createState() => _PhotoFinderScreenState();
}

class _PhotoFinderScreenState extends State<PhotoFinderScreen> {
  final _singleVin = TextEditingController();
  final _singleNo = TextEditingController();
  final Map<String, String> _processed = {};
  bool _syncing = false;
  bool _libraryRefreshPending = false;
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _search = '';
  String _filter = 'all';
  bool _working = false;
  String? _message;
  Map<String, dynamic> get _state => widget.client.photos;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_queueAttachment);
    widget.refreshSignal?.addListener(_libraryChanged);
    _queueAttachment();
  }

  @override
  void didUpdateWidget(covariant PhotoFinderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeListener(_queueAttachment);
      widget.client.addListener(_queueAttachment);
      _processed.clear();
    }
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_libraryChanged);
      widget.refreshSignal?.addListener(_libraryChanged);
    }
    _queueAttachment();
  }

  void _libraryChanged() {
    _processed.clear();
    if (_syncing) _libraryRefreshPending = true;
    _queueAttachment();
  }

  void _queueAttachment() {
    scheduleMicrotask(() {
      if (mounted && !_syncing && !_working) unawaited(_autoAttach());
    });
  }

  Future<void> _autoAttach() async {
    final rows = _rows(_state['vehicles'])
        .where(
          (row) =>
              ['done', 'partial', 'error', 'stopped'].contains(row['status']) &&
              (row['count'] as num? ?? 0) > 0,
        )
        .toList();
    if (rows.isEmpty) return;
    _syncing = true;
    var updated = 0;
    try {
      for (final row in rows) {
        if (!mounted) break;
        final id = row['id'] as String;
        final signature =
            '${_state['output']}|${_state['startedAt']}|${row['vin']}|${row['status']}|${row['count']}';
        if (_processed[id] == signature) continue;
        // Record before invoking: client notifications must not start a second merge.
        _processed[id] = signature;
        try {
          updated += await _attachRow(row);
        } catch (error) {
          if (mounted) {
            setState(
              () => _message =
                  'Automatic poster attachment needs attention: $error. Use photos in posters to retry.',
            );
          }
        }
      }
      if (mounted && updated > 0) widget.onLibraryChanged();
    } finally {
      _syncing = false;
      if (mounted) setState(() {});
      if (_libraryRefreshPending) {
        _libraryRefreshPending = false;
        _queueAttachment();
      }
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_queueAttachment);
    widget.refreshSignal?.removeListener(_libraryChanged);
    _singleVin.dispose();
    _singleNo.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_working || _syncing) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() => _working = false);
        _queueAttachment();
      }
    }
  }

  Future<void> _command(
    String action, [
    Map<String, dynamic> args = const {},
  ]) => _perform(() async {
    await widget.client.invoke('photos.$action', args);
  });

  Future<void> _importDrafts() => _perform(() async {
    final workbook = await widget.client.invoke('photos.workbook-data');
    final vehicles = await VehicleListImporter.fromBytes(
      workbook['filename'] as String,
      base64Decode(workbook['bytes'] as String),
    );
    if (vehicles.isEmpty) {
      throw StateError('No vehicle details were found in this workbook.');
    }
    final existing = await widget.history.list();
    if (!mounted) return;
    final plan = await VehicleDraftImportPlan.prepare(
      vehicles: vehicles,
      existing: existing,
      resolveDuplicate: (conflict) async {
        if (!mounted) {
          return const DuplicateImportDecision(DuplicateImportAction.cancel);
        }
        return await showDialog<DuplicateImportDecision>(
              context: context,
              builder: (_) => DuplicateVehicleDialog(conflict: conflict),
            ) ??
            const DuplicateImportDecision(DuplicateImportAction.cancel);
      },
    );
    if (plan == null) return;
    await widget.history.importVehicleDetails(plan.drafts);
    widget.onLibraryChanged();
    if (mounted) {
      setState(
        () => _message =
            '${plan.addedCount} poster drafts added; ${plan.replacedCount} updated. Downloaded photos attach automatically by VIN. Review flagged slots in History.',
      );
    }
  });

  Future<int> _attachRow(Map<String, dynamic> row) async {
    // Skip decoding when no saved poster has this VIN yet.
    final vin = normalizedVehicleVin(row['vin'] as String);
    if (!(await widget.history.list()).any(
      (entry) => normalizedVehicleVin(entry.vehicle.vin) == vin,
    )) {
      return 0;
    }
    final result = await widget.client.invoke('poster-photos', {
      'id': row['id'],
    });
    if (normalizedVehicleVin(result['vin'] as String? ?? '') != vin) {
      throw StateError('Downloaded photos do not match the requested VIN.');
    }
    final encodedPhotos = result['photos'] as List;
    if (encodedPhotos.length != 4) {
      throw StateError(
        'Update the automation helper to return Front, Interior, Side and Rear slots.',
      );
    }
    final photos = List<Uint8List?>.filled(4, null);
    for (var slot = 0; slot < 4; slot++) {
      final encoded = encodedPhotos[slot];
      if (encoded == null) continue;
      final codec = await ui.instantiateImageCodec(
        base64Decode(encoded as String),
        targetWidth: 2600,
        allowUpscaling: false,
      );
      ui.Image? image;
      try {
        image = (await codec.getNextFrame()).image;
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) {
          throw StateError('Could not process downloaded photo.');
        }
        photos[slot] = bytes.buffer.asUint8List();
      } finally {
        image?.dispose();
        codec.dispose();
      }
    }
    return attachDownloadedPhotos(widget.history, vin, photos);
  }

  Future<void> _attach() => _perform(() async {
    var count = 0;
    for (final row in _rows(_state['vehicles'])) {
      if ((row['count'] as num? ?? 0) == 0 ||
          [
            'queued',
            'searching',
            'downloading',
            'classifying',
          ].contains(row['status'])) {
        continue;
      }
      count += await _attachRow(row);
    }
    widget.onLibraryChanged();
    if (mounted) {
      setState(
        () => _message = count == 0
            ? 'No empty slots updated. Check matching VINs in History. Unidentified views stay blank and flagged for manual selection.'
            : 'Photos added to $count matching posters. Review flagged slots in History.',
      );
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.client,
    builder: (context, _) {
      final state = _state;
      final running = state['running'] == true;
      final rows = _rows(state['vehicles']);
      final missing = rows.where((r) => r['status'] == 'not_found').length;
      final visible = rows.where((r) {
        final status = r['status'];
        if (_filter == 'saved' && status != 'done') return false;
        if (_filter == 'attention' &&
            ![
              'invalid',
              'error',
              'partial',
              'not_found',
              'skipped',
              'stopped',
            ].contains(status) &&
            (r['missingViews'] as List? ?? []).isEmpty) {
          return false;
        }
        return '${r['vin']} ${r['vehicle']} ${r['no']}'.toLowerCase().contains(
          _search.toLowerCase(),
        );
      });
      final ready = !_working && !_syncing && !running;
      return AutomationPanel(
        client: widget.client,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Find photos.\nCreate posters.',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search Bid.Cars and NCA by exact VIN. Photos attach to matching poster drafts automatically: Front, Interior, Side, Rear. Uncertain or missing views stay blank and flagged for manual selection. Photo recognition runs on this computer and downloads its AI model on first use.',
            ),
            const SizedBox(height: 24),
            StudioCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: ready
                            ? () => _command('choose-workbook')
                            : null,
                        icon: const Icon(Icons.table_view),
                        label: Text(
                          (state['filename'] as String? ?? '').isEmpty
                              ? 'Choose Excel workbook'
                              : state['filename'] as String,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: ready
                            ? () => _command('choose-output')
                            : null,
                        icon: const Icon(Icons.folder_outlined),
                        label: const Text('Choose photo folder'),
                      ),
                      TextButton(
                        onPressed:
                            ready &&
                                (state['workbookPath'] as String? ?? '')
                                    .isNotEmpty
                            ? _importDrafts
                            : null,
                        child: const Text('Import list into poster drafts'),
                      ),
                    ],
                  ),
                  if ((state['output'] as String? ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SelectableText(state['output'] as String),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: state['sourceMode'] as String? ?? 'both',
                    decoration: const InputDecoration(
                      labelText: 'Photo source',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'both',
                        child: Text('Bid.Cars, then NCA'),
                      ),
                      DropdownMenuItem(
                        value: 'bidcars',
                        child: Text('Bid.Cars only'),
                      ),
                      DropdownMenuItem(value: 'nca', child: Text('NCA only')),
                    ],
                    onChanged: ready
                        ? (value) => _command('set-source', {'mode': value})
                        : null,
                  ),
                  ExpansionTile(
                    title: Text(
                      state['ncaSignedIn'] == true
                          ? 'NCA sign-in · signed in'
                          : 'NCA sign-in',
                    ),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      TextField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: ready
                            ? () {
                                final password = _password.text;
                                _password.clear();
                                _command('login', {
                                  'email': _email.text,
                                  'password': password,
                                });
                              }
                            : null,
                        child: const Text('Sign in to NCA'),
                      ),
                      const Text(
                        'Your browser session stays on this computer. Your password is not saved.',
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: !_working
                            ? () => _command('open-browser')
                            : null,
                        child: const Text('Open Bid.Cars'),
                      ),
                      TextButton(
                        onPressed: !_working
                            ? () => _command('open-nca')
                            : null,
                        child: const Text('Open NCA'),
                      ),
                      TextButton(
                        onPressed:
                            !_working &&
                                (state['output'] as String? ?? '').isNotEmpty
                            ? () => _command('open-folder')
                            : null,
                        child: const Text('Open destination'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StudioCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Find images for one vehicle',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('single-vehicle-vin'),
                    controller: _singleVin,
                    enabled: ready,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'VIN',
                      hintText: 'Enter the full 17-character VIN',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('single-vehicle-number'),
                    controller: _singleNo,
                    enabled: ready,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'No. (optional)',
                      helperText:
                          'Uses the matching list row, or assigns the next number.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('find-single-vehicle'),
                    onPressed:
                        ready && (state['output'] as String? ?? '').isNotEmpty
                        ? () => _command('search-one', {
                            'vin': _singleVin.text,
                            'no': _singleNo.text,
                          })
                        : null,
                    icon: const Icon(Icons.search),
                    label: const Text('Find and download this vehicle'),
                  ),
                  if ((state['output'] as String? ?? '').isEmpty)
                    const Text('Choose a photo folder above to start.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed:
                      ready &&
                          rows.isNotEmpty &&
                          (state['output'] as String? ?? '').isNotEmpty
                      ? () => _command('start', {'mode': 'all'})
                      : null,
                  icon: const Icon(Icons.download),
                  label: const Text('Download photos'),
                ),
                OutlinedButton(
                  onPressed:
                      ready &&
                          rows.any(
                            (r) => [
                              'error',
                              'partial',
                              'not_found',
                              'skipped',
                              'stopped',
                            ].contains(r['status']),
                          )
                      ? () => _command('start', {'mode': 'retry'})
                      : null,
                  child: const Text('Retry unfinished'),
                ),
                if (running)
                  OutlinedButton(
                    onPressed: () => widget.client
                        .invoke('photos.stop')
                        .catchError((Object error) {
                          if (mounted) {
                            setState(() => _message = error.toString());
                          }
                          return <String, dynamic>{};
                        }),
                    child: const Text('Stop batch'),
                  ),
                FilledButton.tonalIcon(
                  onPressed:
                      ready && rows.any((r) => (r['count'] as num? ?? 0) > 0)
                      ? _attach
                      : null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Use photos in posters'),
                ),
              ],
            ),
            if (_working || _syncing || running)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if ((state['help'] as String? ?? '').isNotEmpty)
              StudioCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state['help'] as String),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: () => _command('continue'),
                          child: const Text('Continue'),
                        ),
                        TextButton(
                          onPressed: () => _command('skip'),
                          child: const Text('Skip vehicle'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _message ?? state['activity'] as String? ?? '',
                key: const ValueKey('photo-activity'),
              ),
            ),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text('${rows.length} vehicles'),
                Text(
                  '${rows.where((r) => r['status'] == 'done').length} saved',
                ),
                Text(
                  '${rows.fold<int>(0, (sum, r) => sum + (r['count'] as num? ?? 0).toInt())} photos',
                ),
                Text('$missing not found'),
                TextButton(
                  onPressed: !_working && rows.isNotEmpty
                      ? () => _command('export-report')
                      : null,
                  child: const Text('Export report'),
                ),
                TextButton(
                  onPressed: !_working && missing > 0
                      ? () => _command('export-not-found')
                      : null,
                  child: Text('Export not found VINs ($missing)'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search VIN, No. or vehicle',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final filter in ['all', 'saved', 'attention'])
                  ChoiceChip(
                    label: Text(
                      filter == 'all'
                          ? 'All vehicles'
                          : filter == 'saved'
                          ? 'Saved'
                          : 'Needs attention',
                    ),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            for (final row in visible)
              Card(
                key: ValueKey('photo-result-${row['id']}'),
                child: ListTile(
                  title: Text('${row['no']}. ${row['vehicle']} ${row['year']}'),
                  subtitle: SelectableText(
                    '${row['vin']}\n${row['status']} · ${row['count']} photos\n${row['message'] ?? ''}${(row['missingViews'] as List? ?? []).isEmpty ? '' : '\n⚑ Select manually: ${(row['missingViews'] as List).join(', ')}'}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => action == 'download-one'
                        ? _command('start', {'mode': 'single', 'id': row['id']})
                        : _command(action, {'id': row['id']}),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'download-one',
                        enabled:
                            ready &&
                            row['status'] != 'invalid' &&
                            (state['output'] as String? ?? '').isNotEmpty,
                        child: const Text('Find images for this vehicle'),
                      ),
                      PopupMenuItem(
                        value: 'open-folder',
                        enabled: (row['count'] as num? ?? 0) > 0,
                        child: const Text('Open photo folder'),
                      ),
                      PopupMenuItem(
                        value: 'open-listing',
                        enabled:
                            !running &&
                            (row['source'] as String? ?? '').isNotEmpty,
                        child: const Text('Open source listing'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class NcaImportScreen extends StatefulWidget {
  const NcaImportScreen({super.key, required this.client});
  final AutomationClient client;
  @override
  State<NcaImportScreen> createState() => _NcaImportScreenState();
}

class _NcaImportScreenState extends State<NcaImportScreen> {
  final _url = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _sheet = TextEditingController();
  final _limit = TextEditingController();
  final _start = TextEditingController();
  bool _working = false;
  bool _optionsChanged = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    for (final controller in [_sheet, _limit, _start]) {
      controller.addListener(() => setState(() => _optionsChanged = true));
    }
  }

  @override
  void dispose() {
    for (final c in [_url, _email, _password, _sheet, _limit, _start]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _command(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.client.invoke('importer.$action', args);
      if (action == 'validate' && mounted) {
        setState(() => _optionsChanged = false);
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _run(bool publish) async {
    final url = _url.text.trim();
    final count = _rows(widget.client.importer['vehicles']).length;
    if (publish) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Publish vehicles to NCA?'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Text(
                '$count validated vehicles will be processed in spreadsheet order.\n\nAuction: $url\n\n'
                'New entries will be published with the validated bidding and reserve prices, Afghanistan / Herat NCA Branch, and On Approval. Existing matching entries are verified and skipped. Conflicts stop the run.\n\nThis changes the live NCA auction.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publish to NCA'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    final password = _password.text;
    _password.clear();
    await _command('start', {
      'url': url,
      'email': _email.text,
      'password': password,
      'mode': publish ? 'publish' : 'preview',
      'confirmed': publish,
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.client,
    builder: (context, _) {
      final state = widget.client.importer;
      final running = state['running'] == true;
      final ready = !_working && !running;
      final vehicles = _rows(state['vehicles']);
      final results = _rows(state['results']);
      final validated = vehicles.isNotEmpty && !_optionsChanged;
      return AutomationPanel(
        client: widget.client,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Your list.\nReady for auction.',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Validate Excel or CSV, preview the forms, then publish to your NCA auction when ready.',
            ),
            const SizedBox(height: 24),
            StudioCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: ready
                            ? () => _command('choose-workbook')
                            : null,
                        icon: const Icon(Icons.table_view),
                        label: Text(
                          (state['filename'] as String? ?? '').isEmpty
                              ? 'Choose Excel or CSV'
                              : state['filename'] as String,
                        ),
                      ),
                      TextButton(
                        onPressed:
                            ready &&
                                (widget.client.photos['filename'] as String? ??
                                        '')
                                    .isNotEmpty
                            ? () => _command('use-workbook')
                            : null,
                        child: const Text('Use Photo Finder workbook'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Worksheet and numbering options'),
                    children: [
                      TextField(
                        controller: _sheet,
                        enabled: ready,
                        decoration: const InputDecoration(
                          labelText: 'Worksheet (blank = first)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _limit,
                        enabled: ready,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle limit (blank = all)',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _start,
                        enabled: ready,
                        decoration: const InputDecoration(
                          labelText:
                              'First new item (blank = highest existing + 1)',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed:
                        ready && (state['file'] as String? ?? '').isNotEmpty
                        ? () => _command('validate', {
                            'sheet': _sheet.text.trim(),
                            'limit': _limit.text.trim(),
                            'startItem': _start.text.trim(),
                          })
                        : null,
                    child: const Text('Validate workbook'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _url,
                    enabled: ready,
                    decoration: const InputDecoration(
                      labelText: 'NCA auction URL',
                      hintText: 'https://my.nca.af/auction/view/…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    enabled: ready,
                    decoration: const InputDecoration(labelText: 'NCA email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: ready,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'NCA password',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Google Chrome is used for preview and publishing. Enter your password for each run; it is not saved.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: ready && validated ? () => _run(false) : null,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview forms'),
                ),
                FilledButton.icon(
                  onPressed: ready && validated ? () => _run(true) : null,
                  icon: const Icon(Icons.publish),
                  label: const Text('Publish to NCA'),
                ),
                if (running)
                  OutlinedButton(
                    onPressed: () => _command('stop'),
                    child: const Text('Stop import'),
                  ),
                if (state['browserOpen'] == true && !running)
                  TextButton(
                    onPressed: ready ? () => _command('close-browser') : null,
                    child: const Text('Close review browser'),
                  ),
                TextButton(
                  onPressed:
                      !_working &&
                          (state['reportDirectory'] as String? ?? '').isNotEmpty
                      ? () => _command('open-reports')
                      : null,
                  child: const Text('Open reports'),
                ),
              ],
            ),
            if (_working || running)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(
                _message ?? state['message'] as String? ?? '',
              ),
            ),
            Text(
              '${vehicles.length} validated vehicles · ${results.length} processed',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final vehicle in vehicles)
              Builder(
                builder: (_) {
                  final matches = results.where(
                    (r) => r['vin'] == vehicle['vin'],
                  );
                  final result = matches.isEmpty ? null : matches.last;
                  return Card(
                    child: ListTile(
                      title: SelectableText(vehicle['vin'] as String),
                      subtitle: Text(
                        'Excel row ${vehicle['row']} · Start: ${vehicle['biddingStart']} · Reserve: ${vehicle['greenLight']}${result == null ? '' : '\n${result['status']}${result['item'] == null ? '' : ' · Item ${result['item']}'}${result['error'] == null ? '' : '\n${result['error']}'}'}',
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}
