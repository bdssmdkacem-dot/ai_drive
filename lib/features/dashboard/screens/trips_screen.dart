import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/themes/app_theme.dart';
import '../../../shared/models/trip.dart';
import '../../../shared/repositories/trip_repository.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final _repo = TripRepository();
  late Future<List<Trip>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.recentTrips();
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<Trip>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final trips = snapshot.data!;
        if (trips.isEmpty) {
          return const Center(
            child: Text('No trips yet', style: TextStyle(color: AppTheme.textSecondary)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: trips.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final trip = trips[i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.route, color: AppTheme.primary),
                title: Text(DateFormat.yMMMd().add_jm().format(trip.startedAt)),
                subtitle: Text(
                  '${trip.distanceKm.toStringAsFixed(1)} km • '
                  'avg ${trip.avgSpeedKmh.toStringAsFixed(0)} km/h',
                ),
                trailing: trip.collisionWarningCount > 0
                    ? Chip(
                        label: Text('${trip.collisionWarningCount} warnings'),
                        backgroundColor: AppTheme.warning.withValues(alpha: 0.2),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: body,
    );
  }
}
