import 'poster.dart';
import 'poster_history.dart';

enum DuplicateImportAction { replace, skip, cancel }

class DuplicateImportDecision {
  final DuplicateImportAction action;
  final int matchIndex;
  final bool applyToRemaining;

  const DuplicateImportDecision(
    this.action, {
    this.matchIndex = 0,
    this.applyToRemaining = false,
  });
}

class VehicleImportMatch {
  final int? id;
  final VehicleDetails vehicle;
  final int? importRow;

  const VehicleImportMatch({required this.vehicle, this.id, this.importRow});
}

class VehicleImportConflict {
  final VehicleDetails incoming;
  // The data-row position, excluding spreadsheet headers and title rows.
  final int importRow;
  final List<VehicleImportMatch> matches;

  const VehicleImportConflict({
    required this.incoming,
    required this.importRow,
    required this.matches,
  });
}

class VehicleDraftImportPlan {
  final List<({int? id, VehicleDetails vehicle})> drafts;
  final int addedCount;
  final int replacedCount;
  final int skippedCount;

  const VehicleDraftImportPlan({
    required this.drafts,
    required this.addedCount,
    required this.replacedCount,
    required this.skippedCount,
  });

  /// Resolves all duplicates before writing anything, so Cancel is safe even
  /// after earlier rows have been accepted. Replacements update the working
  /// identities; skipped rows never affect subsequent duplicate detection.
  static Future<VehicleDraftImportPlan?> prepare({
    required List<VehicleDetails> vehicles,
    required List<PosterHistoryEntry> existing,
    DateTime? importedAt,
    required Future<DuplicateImportDecision> Function(VehicleImportConflict)
    resolveDuplicate,
  }) async {
    final importDate = (importedAt ?? DateTime.now()).toLocal();
    final targets = [
      for (final entry in existing)
        if (_sameDate(entry.labelDate.toLocal(), importDate))
          VehicleImportMatch(id: entry.id, vehicle: entry.vehicle),
    ];
    final changed = <int>{};
    var added = 0;
    var replaced = 0;
    var skipped = 0;
    DuplicateImportAction? remainingAction;

    for (var row = 0; row < vehicles.length; row++) {
      final incoming = vehicles[row];
      final keys = _identityKeys(incoming);
      final indices = [
        for (var index = 0; index < targets.length; index++)
          if (_identityKeys(targets[index].vehicle).any(keys.contains)) index,
      ];
      if (indices.isEmpty) {
        changed.add(targets.length);
        targets.add(VehicleImportMatch(vehicle: incoming, importRow: row + 1));
        added++;
        continue;
      }

      // An ambiguous match must still be reviewed when replacing all.
      final decision =
          remainingAction != null &&
              (remainingAction == DuplicateImportAction.skip ||
                  indices.length == 1)
          ? DuplicateImportDecision(remainingAction)
          : await resolveDuplicate(
              VehicleImportConflict(
                incoming: incoming,
                importRow: row + 1,
                matches: [for (final index in indices) targets[index]],
              ),
            );
      if (decision.action == DuplicateImportAction.cancel) return null;
      if (decision.applyToRemaining) remainingAction = decision.action;
      if (decision.action == DuplicateImportAction.skip) {
        skipped++;
        continue;
      }

      final index = indices[decision.matchIndex];
      targets[index] = VehicleImportMatch(
        id: targets[index].id,
        vehicle: incoming,
        importRow: row + 1,
      );
      changed.add(index);
      replaced++;
    }

    return VehicleDraftImportPlan(
      drafts: [
        for (final index in changed)
          (id: targets[index].id, vehicle: targets[index].vehicle),
      ],
      addedCount: added,
      replacedCount: replaced,
      skippedCount: skipped,
    );
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static Set<String> _identityKeys(VehicleDetails vehicle) {
    final vin = vehicle.vin.trim().toUpperCase();
    final number = vehicle.number.trim().toLowerCase();
    return {
      if (vin.isNotEmpty) 'vin:$vin',
      if (number.isNotEmpty) 'number:$number',
    };
  }
}
