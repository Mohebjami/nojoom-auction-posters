import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'poster.dart';
import 'poster_export.dart';
import 'poster_history.dart';
import 'history_screen.dart';
import 'gallery_export.dart';
import 'studio_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VehiclePosterApp());
}

class VehiclePosterApp extends StatelessWidget {
  const VehiclePosterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vehicle Poster',
      debugShowCheckedModeBanner: false,
      theme: studioTheme(),
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends StatefulWidget {
  final PosterHistory? history;
  const EditorScreen({super.key, this.history});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final ImagePicker _picker = ImagePicker();

  final Map<String, TextEditingController> _controllers = {
    'number': TextEditingController(),
    'title': TextEditingController(),
    'model': TextEditingController(),
    'price': TextEditingController(),
    'color': TextEditingController(),
    'vin': TextEditingController(),
  };

  final List<Uint8List?> _photos = List<Uint8List?>.filled(4, null);

  bool _busy = false;
  int? _pendingSlot;
  int? _draftId;
  bool _dirty = false;
  PosterHistory get _history => widget.history ?? PosterHistory.instance;

  static const List<String> _photoLabels = [
    'Main photo',
    'Top-left photo',
    'Middle-left photo',
    'Bottom-left photo',
  ];

  @override
  void initState() {
    super.initState();

    for (final controller in _controllers.values) {
      controller.addListener(() {
        setState(() => _dirty = true);
      });
    }
    if (!kIsWeb && Platform.isAndroid) {
      _restorePhoto();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _restorePhoto() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final response = await _picker.retrieveLostData();

      if (response.isEmpty) {
        return;
      }

      final directory = await getApplicationSupportDirectory();

      final marker = File('${directory.path}/pending-photo');

      int? slot;

      if (await marker.exists()) {
        slot = int.tryParse(await marker.readAsString());
      }

      if (response.files?.isNotEmpty == true &&
          slot != null &&
          slot >= 0 &&
          slot < 4) {
        final rawBytes = await response.files!.first.readAsBytes();

        final bytes = await _normalizeImage(rawBytes);

        if (mounted) {
          setState(() {
            _photos[slot!] = bytes;
            _dirty = true;
          });
        }
      }

      if (await marker.exists()) {
        await marker.delete();
      }
    } catch (e) {
      _showError('Could not restore image: $e');
    }
  }

  /// Resize only.
  ///
  /// IMPORTANT:
  /// We don't crop here.
  /// BoxFit.cover will crop correctly inside each poster frame.
  Future<Uint8List> _normalizeImage(Uint8List bytes) async {
    ui.Codec? codec;
    ui.Image? image;

    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 2600,
        allowUpscaling: false,
      );

      final frame = await codec.getNextFrame();

      image = frame.image;

      final data = await image.toByteData(format: ui.ImageByteFormat.png);

      if (data == null) {
        throw Exception('Could not process image.');
      }

      return data.buffer.asUint8List();
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  Future<void> _pickPhoto(int slot) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _pendingSlot = slot;
    });

    File? marker;

    try {
      if (!kIsWeb && Platform.isAndroid) {
        final directory = await getApplicationSupportDirectory();

        marker = File('${directory.path}/pending-photo');

        await marker.writeAsString('$slot');
      }

      XFile? result;

      if (!kIsWeb && Platform.isMacOS) {
        result = await _picker.pickImage(
          source: ImageSource.gallery,
          requestFullMetadata: false,
        );
      } else {
        result = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 5000,
          maxHeight: 5000,
          requestFullMetadata: false,
        );
      }

      if (result == null) {
        return;
      }

      final rawBytes = await result.readAsBytes();

      final bytes = await _normalizeImage(rawBytes);

      if (!mounted) return;

      setState(() {
        _photos[slot] = bytes;
        _dirty = true;
      });
    } catch (e) {
      _showError('Could not select image: $e');
    } finally {
      if (marker != null) {
        try {
          if (await marker.exists()) {
            await marker.delete();
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _busy = false;
          _pendingSlot = null;
        });
      }
    }
  }

  void _removePhoto(int index) {
    if (_busy) return;

    setState(() {
      _photos[index] = null;
      _dirty = true;
    });
  }

  String _value(String key) {
    return _controllers[key]?.text.trim() ?? '';
  }

  VehicleDetails get _vehicle => VehicleDetails.fromJson({
    for (final entry in _controllers.entries) entry.key: entry.value.text,
  });

  Future<void> _saveDraft() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await _history.save(_vehicle, _photos, id: _draftId);
      if (!mounted) return;
      setState(() {
        _draftId = id;
        _dirty = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Poster saved to history.')));
    } catch (error) {
      _showError('Could not save poster: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text(
              'Save your draft first to keep these changes, or discard them to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard changes'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _newPoster() async {
    if (!await _confirmDiscard() || !mounted) return;
    setState(() {
      for (final controller in _controllers.values) {
        controller.clear();
      }
      _photos.fillRange(0, 4, null);
      _draftId = null;
      _dirty = false;
    });
  }

  Future<void> _openHistory() async {
    if (!await _confirmDiscard() || !mounted) return;
    final draft = await Navigator.push<PosterDraft>(
      context,
      MaterialPageRoute(builder: (_) => HistoryScreen(history: _history)),
    );
    if (!mounted) return;
    if (draft != null) {
      setState(() {
        for (final entry in draft.vehicle.toJson().entries) {
          _controllers[entry.key]!.text = entry.value;
        }
        _photos.setAll(0, draft.photos);
        _draftId = draft.id;
        _dirty = false;
      });
    } else if (_draftId != null) {
      // The currently edited entry may have been deleted in History.
      try {
        final entries = await _history.list();
        if (mounted && !entries.any((entry) => entry.id == _draftId)) {
          setState(() {
            _draftId = null;
            _dirty = true;
          });
        }
      } catch (error) {
        _showError(error);
      }
    }
  }

  Future<void> _generate() async {
    if (_busy) return;

    setState(() {
      _busy = true;
    });

    try {
      final template = await PosterTemplate.load();

      final vehicle = _vehicle;

      final result = await template.build(vehicle, _photos);
      final id = await _history.save(vehicle, _photos, id: _draftId);

      if (!mounted) return;
      setState(() {
        _draftId = id;
        _dirty = false;
      });

      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PreviewScreen(
            designSvg: result.designSvg,
            exportSvg: result.exportSvg,
            number: _value('number'),
            photos: result.photos,
            logo: result.logo,
            savedToHistory: true,
          ),
        ),
      );
    } catch (e) {
      _showError('Could not generate poster: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Widget _field(
    String key,
    String label,
    String hint, {
    int maxLength = 60,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: _controllers[key],
        enabled: !_busy,
        keyboardType: keyboard,
        maxLength: maxLength,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
          prefixText: key == 'price' ? '\$ ' : null,
        ),
      ),
    );
  }

  Widget _photoCard(int index) {
    final photo = _photos[index];
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      label:
          '${_photoLabels[index]}, ${photo == null ? 'add photo' : 'replace photo'}',
      child: Material(
        color: photo == null ? const Color(0xfff5f5f1) : Colors.black,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: index == 0
                ? accent.withValues(alpha: .35)
                : StudioColors.line,
          ),
        ),
        child: InkWell(
          onTap: _busy ? null : () => _pickPhoto(index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo != null) Image.memory(photo, fit: BoxFit.cover),
              if (photo == null)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      index == 0
                          ? Icons.add_a_photo_outlined
                          : Icons.add_photo_alternate_outlined,
                      size: 30,
                      color: accent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Add photo',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              if (photo != null)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 8,
                bottom: 12,
                child: Text(
                  _photoLabels[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: photo == null ? StudioColors.muted : Colors.white,
                  ),
                ),
              ),
              if (photo != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    tooltip: 'Remove ${_photoLabels[index].toLowerCase()}',
                    onPressed: _busy ? null : () => _removePhoto(index),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              if (_pendingSlot == index)
                const ColoredBox(
                  color: Color(0xb3ffffff),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String step, String title, String subtitle, Widget child) {
    return StudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                step,
                style: const TextStyle(
                  color: StudioColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.5,
                  ),
                ),
              ),
              Icon(
                step == '01'
                    ? Icons.photo_library_outlined
                    : Icons.tune_rounded,
                color: StudioColors.muted,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: StudioColors.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          child,
        ],
      ),
    );
  }

  Widget _photosSection() => _section(
    '01',
    'Vehicle photos',
    '${_photos.where((photo) => photo != null).length} of 4 added • All photos are optional',
    GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (context, index) => _photoCard(index),
    ),
  );

  Widget _detailsSection() => _section(
    '02',
    'Vehicle details',
    'Add the details you want to show on your poster.',
    Column(
      children: [
        _field('title', 'Title', '2010 TOYOTA'),
        _field('model', 'Model', 'COROLLA'),
        Row(
          children: [
            Expanded(
              child: _field(
                'price',
                'Price',
                '6000',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _field('color', 'Color', 'SILVER')),
          ],
        ),
        _field('vin', 'VIN', 'JTDKN3DU2A0090987', maxLength: 17),
        _field(
          'number',
          'Top-left number',
          '2',
          keyboard: TextInputType.number,
          maxLength: 8,
        ),
      ],
    ),
  );

  Widget _summary() {
    final photos = _photos.where((photo) => photo != null).length;
    final fields = _controllers.values
        .where((field) => field.text.trim().isNotEmpty)
        .length;
    final progress = (photos + fields) / 10;
    return StudioCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    backgroundColor: StudioColors.line,
                    color: StudioColors.accent,
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Make it yours',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                Text(
                  '$photos/4 photos  ·  $fields/6 details',
                  style: const TextStyle(
                    color: StudioColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_outward_rounded,
            size: 20,
            color: StudioColors.muted,
          ),
        ],
      ),
    );
  }

  Widget _editorFooter() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: const BoxDecoration(
      color: Color(0xfff8f8f5),
      border: Border(top: BorderSide(color: StudioColors.line)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (constraints.maxWidth >= 600) ...[
            const Icon(Icons.lock_outline, size: 13, color: StudioColors.muted),
            const SizedBox(width: 7),
            const Text(
              'Your work stays on this device',
              style: TextStyle(fontSize: 10, color: StudioColors.muted),
            ),
            const Spacer(),
          ],
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: _busy ? null : _saveDraft,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: Text(
              _draftId == null ? 'Save draft' : 'Save changes',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 17),
              label: Text(
                _busy && _pendingSlot == null
                    ? 'Preparing poster…'
                    : 'Generate poster',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => StudioShell(
    section: 'Create',
    busy: _busy,
    onNew: _newPoster,
    onHistory: _openHistory,
    footer: _editorFooter(),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 16, wide ? 28 : 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: StudioHeading(
                      title: 'Let’s create\nsomething great.',
                      subtitle:
                          'Turn your next vehicle into a lasting first impression.',
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 30),
                    SizedBox(width: 290, child: _summary()),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const StudioBadge(
                    label: 'YOUR CREATIVE WORKSPACE',
                    icon: Icons.grid_view_rounded,
                  ),
                  const Spacer(),
                  if (wide)
                    Text(
                      _draftId == null ? 'New poster' : 'Editing saved poster',
                      style: const TextStyle(
                        fontSize: 11,
                        color: StudioColors.muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _photosSection(),
                          const SizedBox(height: 16),
                          const StudioCard(
                            dark: true,
                            padding: EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline_rounded,
                                  color: Color(0xffe9a486),
                                  size: 26,
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'A great photo goes a long way.',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'Use a clear main shot and a few detail photos.\nWe’ll take care of the layout.',
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 11,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: _detailsSection()),
                  ],
                )
              else ...[
                _summary(),
                const SizedBox(height: 16),
                _photosSection(),
                const SizedBox(height: 16),
                _detailsSection(),
              ],
              const SizedBox(height: 22),
              const Center(
                child: Text(
                  'All fields are optional. Generating a poster saves it to history.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: StudioColors.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// ============================================================================
// PREVIEW
// ============================================================================

class PreviewScreen extends StatefulWidget {
  final String designSvg;
  final String exportSvg;
  final String number;
  final List<Uint8List?> photos;
  final Uint8List logo;
  final bool savedToHistory;

  const PreviewScreen({
    super.key,
    required this.designSvg,
    required this.exportSvg,
    required this.number,
    required this.photos,
    required this.logo,
    this.savedToHistory = false,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  static const double posterWidth = 1621;
  static const double posterHeight = 1987;

  final GlobalKey _posterKey = GlobalKey();

  bool _busy = false;
  Future<void>? _imagesReady;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _imagesReady ??= Future.wait([
      for (final bytes in [
        ...widget.photos.whereType<Uint8List>(),
        widget.logo,
      ])
        precacheImage(MemoryImage(bytes), context),
    ]);
  }

  String get _safeNumber {
    final value = widget.number.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

    return value.isEmpty ? 'poster' : value;
  }

  Future<File> _writeFile({
    required Uint8List bytes,
    required String extension,
  }) async {
    final root = await getTemporaryDirectory();

    final directory = Directory('${root.path}/vehicle-poster-exports');

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final file = File(
      '${directory.path}/vehicle-$_safeNumber-$timestamp.$extension',
    );

    await file.writeAsBytes(bytes, flush: true);

    return file;
  }

  Future<Uint8List> _capturePng() async {
    await _imagesReady;
    await WidgetsBinding.instance.endOfFrame;

    final posterContext = _posterKey.currentContext;

    if (posterContext == null || !posterContext.mounted) {
      throw Exception('Poster is not ready.');
    }

    final renderObject = posterContext.findRenderObject();

    if (renderObject is! RenderRepaintBoundary) {
      throw Exception('Could not capture poster.');
    }

    // The RepaintBoundary itself is 1621 × 1987.
    final ui.Image image = await renderObject.toImage(pixelRatio: 1);

    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);

      if (data == null) {
        throw Exception('Could not create PNG.');
      }

      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _sharePng() async {
    if (_busy) return;

    setState(() {
      _busy = true;
    });

    try {
      final bytes = await _capturePng();

      await _shareBytes(bytes, 'png', 'image/png');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _shareSvg() async {
    if (_busy) return;

    setState(() {
      _busy = true;
    });

    try {
      final bytes = Uint8List.fromList(utf8.encode(widget.exportSvg));

      await _shareBytes(bytes, 'svg', 'image/svg+xml');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _shareBytes(
    Uint8List bytes,
    String extension,
    String mimeType,
  ) async {
    final name = 'vehicle-$_safeNumber.$extension';
    final file = kIsWeb
        ? XFile.fromData(bytes, mimeType: mimeType, name: name)
        : XFile(
            (await _writeFile(bytes: bytes, extension: extension)).path,
            mimeType: mimeType,
          );
    if (!mounted) return;
    Rect? origin;

    final renderObject = context.findRenderObject();

    if (renderObject is RenderBox) {
      origin = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [name],
        title: 'Vehicle Poster',
        subject: 'Vehicle Poster',
        sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
  }

  bool get _usesGallery => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _saveJpg() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_usesGallery) await ensureGalleryAccess();
      if (!mounted) return;
      final bytes = await compute(encodePosterJpg, await _capturePng());
      final name =
          'vehicle-$_safeNumber-${DateTime.now().microsecondsSinceEpoch}.jpg';
      String message;
      if (_usesGallery) {
        await saveJpgToGallery(bytes, name);
        message = 'JPG saved to your gallery.';
      } else if (kIsWeb) {
        await XFile.fromData(
          bytes,
          mimeType: 'image/jpeg',
          name: name,
        ).saveTo(name);
        message = 'JPG download started. Check your browser downloads.';
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'JPEG image',
              extensions: ['jpg', 'jpeg'],
              uniformTypeIdentifiers: ['public.jpeg'],
            ),
          ],
        );
        if (location == null) return;
        await XFile.fromData(
          bytes,
          mimeType: 'image/jpeg',
          name: name,
        ).saveTo(location.path);
        message = 'JPG saved.';
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on GalException catch (error) {
      _showError(
        error.type == GalExceptionType.accessDenied
            ? 'Allow photo saving in your device settings and try again.'
            : error.type.message,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
  }

  Widget _buildPoster() {
    return RepaintBoundary(
      key: _posterKey,
      child: SizedBox(
        width: posterWidth,
        height: posterHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: SvgPicture.string(
                PosterTemplate.backgroundLayer(widget.designSvg),
                width: posterWidth,
                height: posterHeight,
                fit: BoxFit.contain,
              ),
            ),
            for (final frame in PosterTemplate.photoFrames)
              if (frame.slot < widget.photos.length &&
                  widget.photos[frame.slot] != null)
                Positioned.fromRect(
                  rect: frame.bounds,
                  child: Image.memory(
                    widget.photos[frame.slot]!,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
            Positioned.fromRect(
              rect: PosterTemplate.logoBounds,
              child: Image.memory(
                widget.logo,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
            ),
            Positioned.fill(
              child: SvgPicture.string(
                PosterTemplate.foregroundLayer(widget.designSvg),
                width: posterWidth,
                height: posterHeight,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterCanvas() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xffdedfd8),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white),
    ),
    alignment: Alignment.center,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final widthRatio = constraints.maxWidth / posterWidth;
        final heightRatio = constraints.maxHeight / posterHeight;
        final scale = widthRatio < heightRatio ? widthRatio : heightRatio;
        return Container(
          width: posterWidth * scale,
          height: posterHeight * scale,
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .18),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: FittedBox(fit: BoxFit.contain, child: _buildPoster()),
        );
      },
    ),
  );

  Widget _exportPanel({required bool compact}) => StudioCard(
    padding: EdgeInsets.all(compact ? 16 : 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          const StudioBadge(
            label: 'READY TO EXPORT',
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(height: 24),
          const Text(
            'Make your\nnext impression.',
            style: TextStyle(
              fontSize: 27,
              height: 1.1,
              letterSpacing: -1,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your poster is ready. Save it to your device or share it with your next buyer.',
            style: TextStyle(
              color: StudioColors.muted,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            const Icon(
              Icons.aspect_ratio_outlined,
              size: 15,
              color: StudioColors.muted,
            ),
            const SizedBox(width: 8),
            const Text(
              '1621 × 1987 px',
              style: TextStyle(fontSize: 11, color: StudioColors.muted),
            ),
            const Spacer(),
            if (widget.savedToHistory)
              const Text(
                'Saved to history',
                style: TextStyle(fontSize: 10, color: StudioColors.muted),
              ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _saveJpg,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(_usesGallery ? 'Save JPG to gallery' : 'Save JPG'),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _shareSvg,
                child: const Text('Share SVG', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _sharePng,
                child: const Text('Share PNG', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 16),
          const Text(
            'JPG for everyday sharing · PNG for a crisp image · SVG for scalable artwork',
            style: TextStyle(
              color: StudioColors.muted,
              fontSize: 10,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to editing'),
            ),
          ),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => StudioShell(
    section: 'Preview',
    busy: _busy,
    onEditor: () => Navigator.pop(context),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        return Padding(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 14, 10, wide ? 28 : 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StudioHeading(
                title: 'Looking good.',
                subtitle: wide
                    ? 'A final look before your vehicle takes the spotlight.'
                    : 'Your poster, ready for its next chapter.',
              ),
              const SizedBox(height: 20),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _posterCanvas()),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 300,
                            child: SingleChildScrollView(
                              child: _exportPanel(compact: false),
                            ),
                          ),
                        ],
                      )
                    : _posterCanvas(),
              ),
              if (!wide) ...[
                const SizedBox(height: 12),
                _exportPanel(compact: true),
              ],
            ],
          ),
        );
      },
    ),
  );
}
