import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_poster/duplicate_vehicle_dialog.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/vehicle_draft_import.dart';

void main() {
  for (final width in [390.0, 880.0]) {
    for (final action in DuplicateImportAction.values) {
      testWidgets('duplicate dialog returns $action at $width', (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        DuplicateImportDecision? decision;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    decision = await showDialog<DuplicateImportDecision>(
                      context: context,
                      builder: (_) => const DuplicateVehicleDialog(
                        conflict: VehicleImportConflict(
                          incoming: VehicleDetails(number: '1', price: '7000'),
                          importRow: 2,
                          matches: [
                            VehicleImportMatch(
                              vehicle: VehicleDetails(
                                number: '1',
                                price: '6000',
                              ),
                              importRow: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Duplicate vehicle found'), findsOneWidget);
        expect(find.text('Earlier imported data row 1'), findsOneWidget);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(switch (action) {
            DuplicateImportAction.replace => 'Replace',
            DuplicateImportAction.skip => 'Skip',
            DuplicateImportAction.cancel => 'Cancel import',
          }),
        );
        await tester.pumpAndSettle();
        expect(decision?.action, action);
        expect(decision?.applyToRemaining, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
