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
  });
  final AutomationClient client;
  final PosterHistory history;
  final VoidCallback onLibraryChanged;
  @override
  State<PhotoFinderScreen> createState() => _PhotoFinderScreenState();
}

class _PhotoFinderScreenState extends State<PhotoFinderScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _search = '';
  String _filter = 'all';
  bool _working = false;
  String? _message;
  Map<String, dynamic> get _state => widget.client.photos;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
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
            '${plan.addedCount} poster drafts added; ${plan.replacedCount} updated. Download photos, then choose Use photos in posters.',
      );
    }
  });

  Future<void> _attach() => _perform(() async {
    var count = 0;
    for (final row in _rows(_state['vehicles'])) {
      if ((row['count'] as num? ?? 0) == 0) {
        continue;
      }
      final result = await widget.client.invoke('poster-photos', {
        'id': row['id'],
      });
      final photos = <Uint8List>[];
      for (final encoded in result['photos'] as List) {
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
          photos.add(bytes.buffer.asUint8List());
        } finally {
          image?.dispose();
          codec.dispose();
        }
      }
      count += await attachDownloadedPhotos(
        widget.history,
        result['vin'] as String,
        photos,
      );
    }
    widget.onLibraryChanged();
    if (mounted) {
      setState(
        () => _message = count == 0
            ? 'No empty slots updated. Import poster drafts with matching VINs first, or check whether their photo slots are already full.'
            : 'Photos added to $count matching posters. Open History to review and generate them. Existing photo slots were kept.',
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
            ].contains(status)) {
          return false;
        }
        return '${r['vin']} ${r['vehicle']} ${r['no']}'.toLowerCase().contains(
          _search.toLowerCase(),
        );
      });
      final ready = !_working && !running;
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
              'Search Bid.Cars and NCA by exact VIN. Download galleries into numbered folders, then fill your poster drafts.',
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
                        onPressed: ready && rows.isNotEmpty
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
            if (_working || running)
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
                labelText: 'Search VIN or vehicle',
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
                child: ListTile(
                  title: Text('${row['no']}. ${row['vehicle']} ${row['year']}'),
                  subtitle: SelectableText(
                    '${row['vin']}\n${row['status']} · ${row['count']} photos\n${row['message'] ?? ''}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => _command(action, {'id': row['id']}),
                    itemBuilder: (_) => [
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
