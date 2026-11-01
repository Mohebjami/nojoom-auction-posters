import 'dart:typed_data';

import '../poster_history.dart';

const posterPhotoViews = ['Front', 'Interior', 'Side', 'Rear'];

/// Positional slots are Front, Interior, Side, Rear. A missing view stays null;
/// later views must never slide into an earlier empty slot.
Future<int> attachDownloadedPhotos(
  PosterHistory history,
  String vin,
  List<Uint8List?> downloaded,
) => history.attachPhotosByVin(vin, downloaded);
