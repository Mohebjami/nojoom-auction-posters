import 'package:flutter/foundation.dart';

import 'automation_stub.dart'
    if (dart.library.io) 'automation_native.dart'
    as platform;

abstract class AutomationClient extends ChangeNotifier {
  static AutomationClient create() => platform.createAutomationClient();

  Map<String, dynamic> state = {};
  String? error;
  bool connecting = false;
  bool get supported;
  bool get connected => state.isNotEmpty;
  Map<String, dynamic> get photos =>
      Map<String, dynamic>.from(state['photos'] as Map? ?? {});
  Map<String, dynamic> get importer =>
      Map<String, dynamic>.from(state['importer'] as Map? ?? {});

  Future<void> start();
  Future<Map<String, dynamic>> invoke(
    String action, [
    Map<String, dynamic> args = const {},
  ]);
}
