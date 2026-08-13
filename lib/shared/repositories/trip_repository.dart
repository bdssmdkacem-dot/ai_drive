import 'package:isar/isar.dart';

import '../database/database_service.dart';
import '../models/incident.dart';
import '../models/trip.dart';

class TripRepository {
  Isar get _isar => DatabaseService.instance.isar;

  Future<int> startTrip() {
    final trip = Trip()..startedAt = DateTime.now();
    return _isar.writeTxn(() => _isar.trips.put(trip));
  }

  Future<void> endTrip(
    int id, {
    required double distanceKm,
    required double avgSpeedKmh,
    required double maxSpeedKmh,
  }) async {
    await _isar.writeTxn(() async {
      final trip = await _isar.trips.get(id);
      if (trip == null) return;
      trip
        ..endedAt = DateTime.now()
        ..distanceKm = distanceKm
        ..avgSpeedKmh = avgSpeedKmh
        ..maxSpeedKmh = maxSpeedKmh;
      await _isar.trips.put(trip);
    });
  }

  Future<List<Trip>> recentTrips({int limit = 50}) {
    return _isar.trips.where().sortByStartedAtDesc().limit(limit).findAll();
  }

  Future<void> logIncident(Incident incident) async {
    await _isar.writeTxn(() => _isar.incidents.put(incident));
  }

  Future<List<Incident>> recentIncidents({int limit = 50}) {
    return _isar.incidents.where().sortByOccurredAtDesc().limit(limit).findAll();
  }
}
