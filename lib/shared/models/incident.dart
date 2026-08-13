import 'package:isar/isar.dart';

import 'trip.dart';

part 'incident.g.dart';

enum IncidentType {
  collisionWarning,
  hardBrake,
  laneDeparture,
  drowsiness,
  phoneUsage,
  parkingImpact,
  manualClip,
}

@collection
class Incident {
  Id id = Isar.autoIncrement;

  @enumerated
  late IncidentType type;

  late DateTime occurredAt;

  double? latitude;
  double? longitude;

  String? videoPath;
  String? note;

  /// Trip this incident belongs to, if the vehicle was in a trip.
  final trip = IsarLink<Trip>();
}
