import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_poster/vehicle_number_sort.dart';

void main() {
  test('Numbers sort numerically with leading zeros and missing values', () {
    final values = ['10', '', ' 02 ', '1', 'A', '100'];
    values.sort(compareVehicleNumbers);
    expect(values, ['1', ' 02 ', '10', '100', 'A', '']);
    values.sort((a, b) => compareVehicleNumbers(a, b, ascending: false));
    expect(values, ['100', '10', ' 02 ', '1', 'A', '']);
    expect(compareVehicleNumbers('02', '2'), 0);
  });

  test('Following vehicles use number order, stable ties and no wrap', () {
    final entries = [(1, '10'), (2, '2'), (3, '1'), (4, '02'), (5, '')];
    List<(int, String)> following((int, String) current) =>
        followingVehicleEntries(
          entries,
          current,
          numberOf: (entry) => entry.$2,
          sameEntry: (entry, selected) => entry.$1 == selected.$1,
        );
    expect(following((3, '1')), [(2, '2'), (4, '02'), (1, '10'), (5, '')]);
    expect(following((1, '10')), [(5, '')]);
    expect(following((5, '')), isEmpty);
    expect(following((99, '1')), isEmpty);
  });
}
