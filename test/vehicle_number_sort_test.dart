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
}
