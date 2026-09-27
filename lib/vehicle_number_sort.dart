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
