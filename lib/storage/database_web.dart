import 'package:sembast_web/sembast_web.dart';

Future<Database> openHistoryDatabase() =>
    databaseFactoryWeb.openDatabase('vehicle-poster-history');
