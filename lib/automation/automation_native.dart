import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'package:path_provider/path_provider.dart';

import 'automation_client.dart';

AutomationClient createAutomationClient() => _NativeAutomation();

class _NativeAutomation extends AutomationClient {
  Process? _process;
  final _http = HttpClient();
  Timer? _timer;
  int? _port;
  String? _token;
  bool _disposed = false;
  bool _polling = false;

  @override
  bool get supported => Platform.isMacOS;

  @override
  Future<void> start() async {
    if (!supported || connecting || connected || _disposed) return;
    connecting = true;
    error = null;
    notifyListeners();
    try {
      final contents = File(Platform.resolvedExecutable).parent.parent.path;
      final bundled = File(
        '$contents/Resources/nojoom-automation/Nojoom Automation.app/Contents/MacOS/Nojoom Automation',
      );
      final source = Directory('${Directory.current.path}/desktop');
      final development = File(
        '${source.path}/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron',
      );
      final isBundled = await bundled.exists();
      final executable = isBundled ? bundled : development;
      if (!await executable.exists()) {
        throw StateError(
          'The automation helper is missing. Build the combined app with '
          'desktop/scripts/build-mac.sh, or install desktop dependencies for development.',
        );
      }
      final support = await getApplicationSupportDirectory();
      final runtime = Directory('${support.path}/automation');
      await runtime.create(recursive: true);
      final environment = Map<String, String>.from(Platform.environment)
        ..remove('ELECTRON_RUN_AS_NODE');
      final process = await Process.start(executable.path, [
        if (!isBundled) source.path,
        '--runtime',
        runtime.path,
      ], environment: environment);
      if (_disposed) {
        process.kill();
        return;
      }
      _process = process;
      final ready = Completer<void>();
      final diagnostics = StringBuffer();
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            try {
              final data = jsonDecode(line) as Map<String, dynamic>;
              if (data['nojoomAutomation'] == true && !ready.isCompleted) {
                _port = data['port'] as int;
                _token = data['token'] as String;
                ready.complete();
              }
            } catch (_) {
              /* Ignore Electron's non-protocol startup output. */
            }
          });
      process.stderr.transform(utf8.decoder).listen((text) {
        if (diagnostics.length < 2000) diagnostics.write(text);
      });
      unawaited(
        process.exitCode.then((code) {
          if (!ready.isCompleted) {
            ready.completeError(
              StateError('Automation could not start: $diagnostics'),
            );
          } else if (!_disposed && _process == process) {
            _timer?.cancel();
            state = {};
            error =
                'Automation stopped (exit $code). Restart it to continue. $diagnostics';
            notifyListeners();
          }
        }),
      );
      await ready.future.timeout(const Duration(seconds: 30));
      final initial = await _request('/state');
      if (!_disposed) {
        state = initial;
        notifyListeners();
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    } catch (failure) {
      error = failure.toString();
      _process?.kill();
      _process = null;
      _port = null;
      _token = null;
    } finally {
      connecting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _request(
    String route, {
    Map<String, dynamic>? body,
  }) async {
    final port = _port;
    if (port == null) throw StateError('Start automation first.');
    final uri = Uri(scheme: 'http', host: '127.0.0.1', port: port, path: route);
    final request = await _http
        .openUrl(body == null ? 'GET' : 'POST', uri)
        .timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(minutes: 3));
    final data = Map<String, dynamic>.from(
      jsonDecode(await utf8.decoder.bind(response).join()) as Map,
    );
    if (response.statusCode != 200) {
      throw StateError(
        data['error'] as String? ?? 'Automation request failed.',
      );
    }
    return data;
  }

  Future<void> _refresh() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      final next = await _request('/state');
      if (!_disposed) {
        state = next;
        error = null;
        notifyListeners();
      }
    } catch (failure) {
      if (!_disposed) {
        error = failure.toString();
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Future<Map<String, dynamic>> invoke(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    // Native pickers belong to the visible Flutter window, not the hidden helper.
    if (action == 'photos.choose-workbook' ||
        action == 'importer.choose-workbook') {
      final photoWorkbook = action.startsWith('photos.');
      final file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: photoWorkbook ? 'Excel workbook' : 'Excel or CSV',
            extensions: photoWorkbook ? ['xlsx'] : ['xlsx', 'csv'],
          ),
        ],
      );
      if (file == null) return state;
      action = photoWorkbook ? 'photos.import-workbook' : 'importer.use-file';
      args = {'file': file.path};
    } else if (action == 'photos.choose-output') {
      final directory = await getDirectoryPath(
        confirmButtonText: 'Choose photo folder',
      );
      if (directory == null) return state;
      action = 'photos.set-output';
      args = {'directory': directory};
    } else if (action == 'photos.export-report' ||
        action == 'photos.export-not-found') {
      final missing = action.endsWith('export-not-found');
      final report = await _request(
        '/command',
        body: {'action': '$action-data'},
      );
      final location = await getSaveLocation(
        suggestedName: missing
            ? 'not-found-vins.csv'
            : 'auction-photo-report.csv',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'CSV report', extensions: ['csv']),
        ],
      );
      if (location != null) {
        await XFile.fromData(
          Uint8List.fromList(utf8.encode(report['csv'] as String)),
          mimeType: 'text/csv',
        ).saveTo(location.path);
      }
      return state;
    }
    final result = await _request(
      '/command',
      body: {'action': action, 'args': args},
    );
    if (!_disposed && result['photos'] is Map && result['importer'] is Map) {
      state = result;
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _http.close(force: true);
    _process?.stdin.close();
    _process?.kill();
    super.dispose();
  }
}
