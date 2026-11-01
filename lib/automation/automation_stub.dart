import 'automation_client.dart';

AutomationClient createAutomationClient() => _UnavailableAutomation();

class _UnavailableAutomation extends AutomationClient {
  @override
  bool get supported => false;
  @override
  Future<void> start() async {}
  @override
  Future<Map<String, dynamic>> invoke(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async =>
      throw UnsupportedError('Open the combined Mac app to use automation.');
}
