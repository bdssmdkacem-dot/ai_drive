import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/incident.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';

/// Single Isar instance for the whole app. Everything is stored locally —
/// there is no backend / cloud sync in v1.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Isar? _isar;

  Isar get isar {
    final db = _isar;
    if (db == null) {
      throw StateError('DatabaseService.init() must be called before use.');
    }
    return db;
  }

  Future<void> init() async {
    if (_isar != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [TripSchema, IncidentSchema, VehicleSchema],
      directory: dir.path,
      name: 'ai_drive_db',
    );
  }
}
