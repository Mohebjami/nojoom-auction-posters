import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/vehicle_brand.dart';

void main() {
  test('recognizes model names without guessing unknown brands', () {
    expect(VehicleBrand.complete('2012', 'prius C'), 'TOYOTA 2012');
    expect(VehicleBrand.complete('', 'Land Cruiser 2015'), 'TOYOTA 2015');
    expect(VehicleBrand.complete('2016', 'C 200'), 'MERCEDES-BENZ 2016');
    expect(VehicleBrand.complete('', 'Mercedes-Benz E350'), 'MERCEDES-BENZ');
    expect(VehicleBrand.complete('LEXUS 2016', 'Prius'), 'LEXUS 2016');
    expect(VehicleBrand.complete('', 'Unknown model'), isEmpty);
    expect(VehicleBrand.fromModel('Priuslike'), isEmpty);
  });

  test('Corolla S Class is Toyota while standalone classes remain Mercedes', () {
    for (final model in ['Corolla S Class', 'COROLLA S-CLASS', 'CROLLA S CLASS']) {
      expect(VehicleBrand.fromModel(model), 'TOYOTA');
      expect(VehicleBrand.complete('2013', model), 'TOYOTA 2013');
    }
    for (final model in ['S Class', 'S-Class', 'C Class', 'E-Class']) {
      expect(VehicleBrand.fromModel(model), 'MERCEDES-BENZ');
    }
  });

  testWidgets('manual model entry fills brand and preserves manual overrides', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditorScreen()));
    final model = find.widgetWithText(TextField, 'Model');
    final title = find.widgetWithText(TextField, 'Brand and year');
    await tester.enterText(title, '2015');
    await tester.enterText(model, 'Prius');
    await tester.pump();
    expect(tester.widget<TextField>(title).controller!.text, 'TOYOTA 2015');
    await tester.enterText(model, 'Benz C200');
    await tester.pump();
    expect(
      tester.widget<TextField>(title).controller!.text,
      'MERCEDES-BENZ 2015',
    );
    await tester.enterText(title, 'CUSTOM 2016');
    await tester.enterText(model, 'Corolla');
    await tester.pump();
    expect(tester.widget<TextField>(title).controller!.text, 'CUSTOM 2016');
  });
}
