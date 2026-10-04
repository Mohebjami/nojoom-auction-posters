/// Compares vehicle numbers numerically, with missing numbers always last.
int compareVehicleNumbers(String a, String b, {bool ascending = true}) {
  final left = a.trim();
  final right = b.trim();
  if (left.isEmpty || right.isEmpty) {
    if (left.isEmpty && right.isEmpty) return 0;
    return left.isEmpty ? 1 : -1;
  }
  final leftNumber = BigInt.tryParse(left);
  final rightNumber = BigInt.tryParse(right);
  final int comparison;
  if (leftNumber != null && rightNumber != null) {
    comparison = leftNumber.compareTo(rightNumber);
  } else if (leftNumber != null) {
    return -1;
  } else if (rightNumber != null) {
    return 1;
  } else {
    comparison = left.toLowerCase().compareTo(right.toLowerCase());
  }
  return ascending ? comparison : -comparison;
}

/// Captures the remaining editing order before any vehicle is renumbered.
/// Equal numbers keep their original order; reaching the end never wraps.
List<T> followingVehicleEntries<T>(
  Iterable<T> entries,
  T current, {
  required String Function(T entry) numberOf,
  required bool Function(T entry, T current) sameEntry,
}) {
  final ordered = entries.indexed.toList()
    ..sort((a, b) {
      final order = compareVehicleNumbers(numberOf(a.$2), numberOf(b.$2));
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
  final index = ordered.indexWhere((item) => sameEntry(item.$2, current));
  if (index < 0) return [];
  return ordered.skip(index + 1).map((item) => item.$2).toList();
}
