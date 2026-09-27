import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/studio_ui.dart';

class _RouteCounter extends NavigatorObserver {
  var pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

Future<void> _settleStorage(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('workspace tabs keep page state without pushing a route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('workspace-tabs'),
    ))!;
    addTearDown(database.close);
    final history = PosterHistory(openDatabase: () async => database);
    final observer = _RouteCounter();

    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        navigatorObservers: [observer],
        home: WorkspaceScreen(history: history),
      ),
    );
    await _settleStorage(tester);
    final initialPushes = observer.pushes;

    await tester.tap(find.byKey(const ValueKey('studio-tab-auction-list')));
    await _settleStorage(tester);
    expect(find.text('Auction\nvehicle list.'), findsOneWidget);
    expect(find.byType(StudioShell), findsOneWidget);

    final search = find.byType(TextField);
    await tester.enterText(search, 'corolla');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('studio-tab-history')));
    await _settleStorage(tester);
    expect(find.text('Good work.\nAll in one place.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('studio-tab-auction-list')));
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, 'corolla');
    expect(observer.pushes, initialPushes);
  });
}
