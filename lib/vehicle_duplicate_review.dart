import 'poster_history.dart';
import 'vehicle_draft_import.dart';

class VehicleDuplicateReviewPlan {
  final List<int> deletedIds;
  final int duplicateGroups;

  const VehicleDuplicateReviewPlan({
    required this.deletedIds,
    required this.duplicateGroups,
  });

  /// Review every VIN across all saved dates before deleting anything.
  /// Original save/import dates define previous and new, not later edits.
  static Future<VehicleDuplicateReviewPlan?> prepare({
    required List<PosterHistoryEntry> existing,
    required Future<DuplicateImportDecision> Function(VehicleImportConflict)
    resolveDuplicate,
  }) async {
    final sorted = [...existing]
      ..sort((a, b) {
        final date = a.labelDate.compareTo(b.labelDate);
        return date != 0 ? date : a.id.compareTo(b.id);
      });
    final groups = <String, List<PosterHistoryEntry>>{};
    for (final entry in sorted) {
      final vin = normalizedVehicleVin(entry.vehicle.vin);
      if (vin.isNotEmpty) (groups[vin] ??= []).add(entry);
    }
    final deletedIds = <int>[];
    var duplicateGroups = 0;
    DuplicateImportAction? remainingAction;
    for (final group in groups.values.where((group) => group.length > 1)) {
      duplicateGroups++;
      final decision = remainingAction != null
          ? DuplicateImportDecision(remainingAction)
          : await resolveDuplicate(
              VehicleImportConflict(
                incoming: group.last.vehicle,
                importRow: 0,
                matches: [
                  for (final entry in group.take(group.length - 1))
                    VehicleImportMatch(id: entry.id, vehicle: entry.vehicle),
                ],
              ),
            );
      if (decision.action == DuplicateImportAction.cancel) return null;
      if (decision.applyToRemaining) remainingAction = decision.action;
      switch (decision.action) {
        case DuplicateImportAction.replace:
          deletedIds.addAll(group.take(group.length - 1).map((e) => e.id));
        case DuplicateImportAction.skip:
          deletedIds.addAll(group.skip(1).map((e) => e.id));
        case DuplicateImportAction.keepBoth:
          break;
        case DuplicateImportAction.cancel:
          return null;
      }
    }
    return VehicleDuplicateReviewPlan(
      deletedIds: deletedIds,
      duplicateGroups: duplicateGroups,
    );
  }
}
