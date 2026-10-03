import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdf/pdf.dart';

import 'custom_template.dart';
import 'poster.dart';
import 'poster_export.dart';
import 'poster_history.dart';

enum BatchPosterFormat { jpgZip, pdf }

class BatchPosterExport {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int count;

  const BatchPosterExport({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.count,
  });
}

class BatchPosterExportCancelled implements Exception {
  const BatchPosterExportCancelled();

  @override
  String toString() => 'Poster export cancelled.';
}

class BatchPosterExportException implements Exception {
  final int posterId;
  final String message;

  const BatchPosterExportException(this.posterId, this.message);

  @override
  String toString() => message;
}

/// Generates in the requested order, loading and rendering one draft at a time.
///
/// Missing photo slots remain empty, just as in the editor. A missing or invalid
/// draft fails the whole operation so the caller never shares a partial batch.
Future<BatchPosterExport> generateBatchPosters({
  required PosterHistory history,
  required List<int> ids,
  required BatchPosterFormat format,
  void Function(int completed, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final posterIds = List<int>.unmodifiable(ids);
  if (posterIds.isEmpty) {
    throw ArgumentError('Choose at least one saved poster to export.');
  }
  if (posterIds.toSet().length != posterIds.length) {
    throw ArgumentError('Choose each saved poster only once.');
  }

  void checkCancelled() {
    if (isCancelled?.call() ?? false) {
      throw const BatchPosterExportCancelled();
    }
  }

  checkCancelled();
  onProgress?.call(0, posterIds.length);
  final original = await PosterTemplate.load();
  checkCancelled();
  final zipOutput = format == BatchPosterFormat.jpgZip
      ? OutputMemoryStream()
      : null;
  final zip = zipOutput == null ? null : (ZipEncoder()..startEncode(zipOutput));
  final pdf = format == BatchPosterFormat.pdf ? PdfDocument() : null;

  for (var index = 0; index < posterIds.length; index++) {
    checkCancelled();
    final id = posterIds[index];
    PosterDraft? draft;
    try {
      draft = await history.load(id);
      checkCancelled();
      final customSource = draft.templateSvg;
      final poster = customSource == null
          ? await original.build(draft.vehicle, draft.photos)
          : await CustomPosterTemplate.parse(
              draft.templateName ?? 'Saved template',
              customSource,
            ).build(draft.vehicle, draft.photos, original.logo);
      checkCancelled();
      final png = poster.previewImage ?? await _renderOriginal(poster);
      checkCancelled();
      final jpg = await compute(encodePosterJpg, png);
      checkCancelled();

      if (zip != null) {
        // JPEG is already compressed. Store it directly, releasing each draft
        // and its large intermediate images before rendering the next one.
        zip.add(
          ArchiveFile.noCompress(
            _posterFileName(draft, index, posterIds.length),
            jpg.length,
            jpg,
          ),
        );
      } else {
        final size = poster.canvasSize;
        // Each page retains its template's own dimensions and aspect ratio.
        final page = PdfPage(
          pdf!,
          pageFormat: PdfPageFormat(size.width, size.height, marginAll: 0),
        );
        page.getGraphics().drawImage(
          PdfImage.jpeg(pdf, image: jpg),
          0,
          0,
          size.width,
          size.height,
        );
      }
    } on BatchPosterExportCancelled {
      rethrow;
    } catch (error) {
      final label = draft?.vehicle.number.trim();
      final name = label == null || label.isEmpty ? '${index + 1}' : label;
      throw BatchPosterExportException(
        id,
        'Could not generate poster $name: $error',
      );
    }
    onProgress?.call(index + 1, posterIds.length);
    // Let the progress indicator and cancellation action update on web too.
    await Future<void>.delayed(Duration.zero);
  }

  checkCancelled();
  final Uint8List bytes;
  if (zip != null) {
    zip.endEncode();
    bytes = zipOutput!.getBytes();
  } else {
    bytes = await pdf!.save(enableEventLoopBalancing: true);
  }
  checkCancelled();
  final extension = format == BatchPosterFormat.pdf ? 'pdf' : 'zip';
  return BatchPosterExport(
    bytes: bytes,
    fileName: 'vehicle-posters-${posterIds.length}.$extension',
    mimeType: format == BatchPosterFormat.pdf
        ? 'application/pdf'
        : 'application/zip',
    count: posterIds.length,
  );
}

String _posterFileName(PosterDraft draft, int index, int total) {
  final label = [
    draft.vehicle.number,
    draft.vehicle.title,
    draft.vehicle.model,
  ].where((value) => value.trim().isNotEmpty).join('-');
  var safe = label
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (safe.isEmpty) safe = 'poster';
  if (safe.length > 100) safe = safe.substring(0, 100);
  final sequence = (index + 1).toString().padLeft(
    math.max(3, total.toString().length),
    '0',
  );
  return '$sequence-$safe.jpg';
}

/// Mirrors PreviewScreen's paint order. Embedded raster images in the export
/// SVG are intentionally drawn separately, using the already cropped pixels.
Future<Uint8List> _renderOriginal(GeneratedPoster poster) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final pictures = <ui.Picture>[];
  final images = <ui.Image>[];
  ui.Picture? composed;
  ui.Image? raster;

  Future<void> drawSvg(String source) async {
    final info = await vg.loadPicture(SvgStringLoader(source), null);
    pictures.add(info.picture);
    canvas.drawPicture(info.picture);
  }

  Future<void> drawImage(Uint8List bytes, ui.Rect bounds) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final image = (await codec.getNextFrame()).image;
      images.add(image);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        bounds,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
    } finally {
      codec.dispose();
    }
  }

  try {
    await drawSvg(PosterTemplate.backgroundLayer(poster.designSvg));
    for (final frame in PosterTemplate.photoFrames) {
      final photo = poster.photos[frame.slot];
      if (photo != null) await drawImage(photo, frame.bounds);
    }
    await drawImage(poster.logo, PosterTemplate.logoBounds);
    await drawSvg(PosterTemplate.foregroundLayer(poster.designSvg));
    composed = recorder.endRecording();
    raster = await composed.toImage(
      poster.canvasSize.width.ceil(),
      poster.canvasSize.height.ceil(),
    );
    final data = await raster.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not render the poster.');
    return data.buffer.asUint8List();
  } finally {
    if (recorder.isRecording) recorder.endRecording().dispose();
    raster?.dispose();
    composed?.dispose();
    for (final image in images) {
      image.dispose();
    }
    for (final picture in pictures) {
      picture.dispose();
    }
  }
}
