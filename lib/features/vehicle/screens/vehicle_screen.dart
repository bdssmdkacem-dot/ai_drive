import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../../../shared/database/database_service.dart';
import '../../../shared/models/vehicle.dart';

class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  final _nameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  late Future<List<Vehicle>> _future;

  Isar get _isar => DatabaseService.instance.isar;

  @override
  void initState() {
    super.initState();
    _future = _isar.vehicles.where().findAll();
  }

  Future<void> _add() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final vehicle = Vehicle()
      ..name = _nameCtrl.text.trim()
      ..plateNumber = _plateCtrl.text.trim();
    await _isar.writeTxn(() => _isar.vehicles.put(vehicle));
    _nameCtrl.clear();
    _plateCtrl.clear();
    setState(() => _future = _isar.vehicles.where().findAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicles')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Vehicle name'),
            ),
            TextField(
              controller: _plateCtrl,
              decoration: const InputDecoration(labelText: 'Plate number'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _add, child: const Text('Add Vehicle')),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<Vehicle>>(
                future: _future,
                builder: (context, snapshot) {
                  final vehicles = snapshot.data ?? [];
                  return ListView.builder(
                    itemCount: vehicles.length,
                    itemBuilder: (context, i) {
                      final v = vehicles[i];
                      return ListTile(
                        leading: const Icon(Icons.directions_car),
                        title: Text(v.name),
                        subtitle: Text(v.plateNumber ?? ''),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
