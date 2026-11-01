import 'dart:typed_data';

import '../poster_history.dart';
import '../vehicle_draft_import.dart';

/// Fills only empty slots on every draft with this exact normalized VIN.
/// Existing pictures, vehicle details, templates and original dates stay intact.
Future<int> attachDownloadedPhotos(
  PosterHistory history,
  String vin,
  List<Uint8List> downloaded,
) async {
  final identity = normalizedVehicleVin(vin);
  if (identity.isEmpty || downloaded.isEmpty) return 0;
  var updated = 0;
  for (final entry in await history.list()) {
    if (normalizedVehicleVin(entry.vehicle.vin) != identity) continue;
    final draft = await history.load(entry.id);
    final photos = List<Uint8List?>.from(draft.photos);
    var source = 0;
    var changed = false;
    for (
      var slot = 0;
      slot < photos.length && source < downloaded.length;
      slot++
    ) {
      if (photos[slot] == null) {
        photos[slot] = downloaded[source++];
        changed = true;
      }
    }
    if (!changed) continue;
    await history.save(
      draft.vehicle,
      photos,
      id: draft.id,
      templateSvg: draft.templateSvg,
      templateName: draft.templateName,
      section: draft.section,
    );
    updated++;
  }
  return updated;
}
