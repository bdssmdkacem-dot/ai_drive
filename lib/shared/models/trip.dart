import 'package:isar/isar.dart';

part 'trip.g.dart';

@collection
class Trip {
  Id id = Isar.autoIncrement;

  late DateTime startedAt;
  DateTime? endedAt;

  double distanceKm = 0;
  double avgSpeedKmh = 0;
  double maxSpeedKmh = 0;

  int hardBrakeCount = 0;
  int collisionWarningCount = 0;
  int drowsinessWarningCount = 0;
  int laneDepartureCount = 0;

  String? startAddress;
  String? endAddress;

  /// Path to the primary dashcam clip associated with this trip, if any.
  String? videoPath;
}
