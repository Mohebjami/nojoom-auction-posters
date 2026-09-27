import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/auction_vehicles_screen.dart';
import 'package:vehicle_poster/auction_vehicle.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/studio_ui.dart';

Future<void> _settleStorage(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 880.0]) {
    testWidgets('Auction number sorting works at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('auction-sort-$width'),
      ))!;
      addTearDown(database.close);
      final history = PosterHistory(openDatabase: () async => database);
      await tester.runAsync(() async {
        for (final number in ['10', '2', '1']) {
          await history.createAuctionVehicle(
            AuctionVehicle(number: number, vehicleType: 'Vehicle $number'),
          );
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: AuctionVehiclesScreen(history: history),
        ),
      );
      await _settleStorage(tester);
      List<String> visibleNumbers() => tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .where(
            (text) => width >= 880
                ? ['1', '2', '10'].contains(text)
                : text.startsWith('NO. '),
          )
          .toList();
      expect(
        visibleNumbers(),
        width >= 880 ? ['1', '2', '10'] : ['NO. 1', 'NO. 2', 'NO. 10'],
      );
      await tester.tap(find.text('Number: low to high'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Number: high to low').last);
      await tester.pumpAndSettle();
      expect(
        visibleNumbers(),
        width >= 880 ? ['10', '2', '1'] : ['NO. 10', 'NO. 2', 'NO. 1'],
      );
      await tester.enterText(find.byType(TextField), 'Vehicle 1');
      await tester.pumpAndSettle();
      expect(
        visibleNumbers(),
        width >= 880 ? ['10', '1'] : ['NO. 10', 'NO. 1'],
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Auction list allows blank mileage and prices', (tester) async {
    final database = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('auction-screen'),
    ))!;
    addTearDown(database.close);
    final history = PosterHistory(openDatabase: () async => database);

    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: AuctionVehiclesScreen(history: history),
      ),
    );
    await _settleStorage(tester);
    expect(find.text('Add your first auction vehicle'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add vehicle').first);
    await tester.pumpAndSettle();
    expect(find.text('Add auction vehicle'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(10));

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '1');
    await tester.enterText(fields.at(1), 'JTDKN3DU0A0231040');
    await tester.enterText(fields.at(2), 'Prius');
    await tester.enterText(fields.at(3), '2010');
    await tester.enterText(fields.at(5), 'White');
    await tester.enterText(fields.at(6), 'Outside');
    await tester.tap(find.widgetWithText(FilledButton, 'Add vehicle').last);
    await _settleStorage(tester);

    final entries = (await tester.runAsync(history.listAuctionVehicles))!;
    expect(entries, hasLength(1));
    expect(entries.single.vehicle.toJson(), {
      'number': '1',
      'vin': 'JTDKN3DU0A0231040',
      'vehicleType': 'Prius',
      'year': '2010',
      'mileage': '',
      'color': 'White',
      'owner': 'Outside',
      'redLight': '',
      'greenLight': '',
      'priceUsd': '',
    });
    expect(find.textContaining('Prius'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
