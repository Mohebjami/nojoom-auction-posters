import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openHistoryDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final current = File('${directory.path}/poster-history.db');
  // The combined Mac app runs outside App Sandbox so its automation helper can
  // launch Chrome. Reuse the previous app's database at its original location.
  // Nothing is moved or deleted; the original bundle identifier is retained.
  if (Platform.isMacOS && !await current.exists()) {
    final home = Platform.environment['HOME'];
    if (home != null) {
      final legacy = File(
        '$home/Library/Containers/com.vehicleposter.vehiclePoster/Data/Library/'
        'Application Support/com.vehicleposter.vehiclePoster/poster-history.db',
      );
      if (await legacy.exists()) {
        return databaseFactoryIo.openDatabase(legacy.path);
      }
    }
  }
  await directory.create(recursive: true);
  return databaseFactoryIo.openDatabase(current.path);
}
