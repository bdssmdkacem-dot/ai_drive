import 'package:isar/isar.dart';

part 'vehicle.g.dart';

@collection
class Vehicle {
  Id id = Isar.autoIncrement;

  late String name;
  String? make;
  String? model;
  int? year;
  String? plateNumber;
  double? odometerKm;
  bool isActive = true;
}
