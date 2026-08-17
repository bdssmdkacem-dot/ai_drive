import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/themes/app_theme.dart';
import '../../ai/models/tracked_object.dart';
import '../../ai/services/collision_prediction_service.dart';
import '../../lane_detection/services/lane_detection_service.dart';

/// Real-time 3D road-scene layer built with a lightweight software 3D
/// projection. It renders a road plane, lane geometry, an ego vehicle and
/// detected objects as perspective-projected cuboids.
///
/// This deliberately avoids a heavy 3D engine: the ADAS scene is generated
/// from the perception pipeline's normalized coordinates and relative depth
/// proxy, so it stays fast on Android and can be drawn directly above the
/// driving UI. It is a true 3D coordinate/projection layer, not a collection
/// of flat screen-space rectangles.
class TeslaVisualizationView extends StatefulWidget {
  const TeslaVisualizationView({
    super.key,
    required this.trackedObjects,
    required this.risk,
    this.laneReading,
    this.speedKmh,
  });

  final List<TrackedObject> trackedObjects;
  final RiskAssessment? risk;
  final LaneReading? laneReading;
  final double? speedKmh;

  @override
  State<TeslaVisualizationView> createState() => _TeslaVisualizationViewState();
}

class _TeslaVisualizationViewState extends State<TeslaVisualizationView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final Map<int, _SceneObject> _objects = {};
  double _roadPhase = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(_tick)
      ..repeat();
  }

  void _tick() {
    final ids = <int>{};
    for (final object in widget.trackedObjects) {
      ids.add(object.trackingId);
      final target = _SceneObject.fromTrackedObject(object);
      _objects[object.trackingId] = _objects[object.trackingId]?.lerpTo(target, 0.22) ?? target;
    }
    _objects.removeWhere((id, _) => !ids.contains(id));

    final speed = widget.speedKmh ?? 35.0;
    _roadPhase = (_roadPhase + speed * 0.00035) % 1.0;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RoadScene3DPainter(
                  objects: _objects.values.toList(growable: false),
                  risk: widget.risk,
                  laneReading: widget.laneReading,
                  roadPhase: _roadPhase,
                ),
              ),
            ),
            if (widget.speedKmh != null)
              Positioned(
                top: 20,
                right: 20,
                child: _SpeedReadout(speedKmh: widget.speedKmh!),
              ),
          ],
        );
      },
    );
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({required this.speedKmh});
  final double speedKmh;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              speedKmh.round().toString(),
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w200),
            ),
            const SizedBox(width: 5),
            const Padding(
              padding: EdgeInsets.only(bottom: 5),
              child: Text('km/h', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneObject {
  const _SceneObject({
    required this.id,
    required this.x,
    required this.depth,
    required this.category,
    required this.size,
  });

  factory _SceneObject.fromTrackedObject(TrackedObject object) {
    final centerX = (object.boundingBox.left + object.boundingBox.width / 2) / object.frameWidth;
    final depth = object.closenessScore.clamp(0.01, 0.95);
    final size = object.category == RoadObjectCategory.person ? 0.65 : 1.35;
    return _SceneObject(
      id: object.trackingId,
      x: (centerX - 0.5).clamp(-0.95, 0.95),
      depth: depth,
      category: object.category,
      size: size,
    );
  }

  final int id;
  final double x;
  final double depth;
  final RoadObjectCategory category;
  final double size;

  _SceneObject lerpTo(_SceneObject target, double t) {
    return _SceneObject(
      id: id,
      x: x + (target.x - x) * t,
      depth: depth + (target.depth - depth) * t,
      category: target.category,
      size: size + (target.size - size) * t,
    );
  }
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

class _ProjectedBox {
  const _ProjectedBox(this.points);
  final List<Offset> points;
}

class _RoadScene3DPainter extends CustomPainter {
  _RoadScene3DPainter({
    required this.objects,
    required this.risk,
    required this.laneReading,
    required this.roadPhase,
  });

  final List<_SceneObject> objects;
  final RiskAssessment? risk;
  final LaneReading? laneReading;
  final double roadPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF071018), Color(0xFF020407)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final focal = math.min(size.width, size.height) * 0.92;
    final horizon = size.height * 0.28;
    const cameraY = 1.65;

    Offset project(_Vec3 p) {
      final z = math.max(p.z, 0.2);
      return Offset(
        size.width / 2 + p.x * focal / z,
        horizon + (cameraY - p.y) * focal / z,
      );
    }

    _drawRoad(canvas, size, project);
    _drawLaneGeometry(canvas, size, project);

    // Draw far objects first so the nearer cuboids naturally overlap them.
    final sorted = [...objects]..sort((a, b) => b.depth.compareTo(a.depth));
    for (final object in sorted) {
      _drawObject(canvas, size, project, object);
    }

    _drawEgoVehicle(canvas, size, project);
    _drawHud(canvas, size);
  }

  void _drawRoad(Canvas canvas, Size size, Offset Function(_Vec3) project) {
    final farLeft = project(const _Vec3(-24, 0, 50));
    final farRight = project(const _Vec3(24, 0, 50));
    final nearRight = project(const _Vec3(5.8, 0, 3.0));
    final nearLeft = project(const _Vec3(-5.8, 0, 3.0));

    final road = Path()
      ..moveTo(farLeft.dx, farLeft.dy)
      ..lineTo(farRight.dx, farRight.dy)
      ..lineTo(nearRight.dx, nearRight.dy)
      ..lineTo(nearLeft.dx, nearLeft.dy)
      ..close();
    canvas.drawPath(road, Paint()..color = const Color(0xFF18212A));

    final shoulder = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawLine(farLeft, nearLeft, shoulder);
    canvas.drawLine(farRight, nearRight, shoulder);
  }

  void _drawLaneGeometry(Canvas canvas, Size size, Offset Function(_Vec3) project) {
    final leftBottom = (laneReading?.leftLineX ?? 0.30).clamp(0.05, 0.48);
    final rightBottom = (laneReading?.rightLineX ?? 0.70).clamp(0.52, 0.95);

    final vp = project(const _Vec3(0, 0, 50));
    final leftNear = Offset(size.width * leftBottom, size.height * 0.96);
    final rightNear = Offset(size.width * rightBottom, size.height * 0.96);

    final lanePaint = Paint()
      ..color = laneReading == null
          ? Colors.white.withValues(alpha: 0.24)
          : AppTheme.primary.withValues(alpha: 0.88)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(vp, leftNear, lanePaint);
    canvas.drawLine(vp, rightNear, lanePaint);

    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 2.2;
    for (var i = 0; i < 8; i++) {
      final z0 = 4.0 + i * 5.0 + roadPhase * 5.0;
      final z1 = z0 + 2.0;
      if (z0 > 48) continue;
      canvas.drawLine(project(_Vec3(0, 0.015, z0)), project(_Vec3(0, 0.015, z1)), dashPaint);
    }
  }

  void _drawObject(
    Canvas canvas,
    Size size,
    Offset Function(_Vec3) project,
    _SceneObject object,
  ) {
    final z = 4.0 + (1.0 - object.depth) * 42.0;
    final x = object.x * z * 0.72;
    final isRisk = risk?.object.trackingId == object.id &&
        (risk?.level == RiskLevel.warning || risk?.level == RiskLevel.danger);
    final color = isRisk
        ? (risk!.level == RiskLevel.danger ? AppTheme.danger : AppTheme.warning)
        : object.category == RoadObjectCategory.person
            ? AppTheme.warning
            : AppTheme.textSecondary;

    final width = object.size * (0.75 + (1.0 - object.depth) * 0.7);
    final height = object.category == RoadObjectCategory.person ? object.size * 1.9 : object.size * 0.85;
    final box = _ProjectedBox([
      project(_Vec3(x - width / 2, 0.02, z)),
      project(_Vec3(x + width / 2, 0.02, z)),
      project(_Vec3(x + width / 2, height, z)),
      project(_Vec3(x - width / 2, height, z)),
      project(_Vec3(x - width / 2, 0.02, z + width * 0.8)),
      project(_Vec3(x + width / 2, 0.02, z + width * 0.8)),
      project(_Vec3(x + width / 2, height, z + width * 0.8)),
      project(_Vec3(x - width / 2, height, z + width * 0.8)),
    ]);

    final p = box.points;
    final front = Path()
      ..moveTo(p[0].dx, p[0].dy)
      ..lineTo(p[1].dx, p[1].dy)
      ..lineTo(p[2].dx, p[2].dy)
      ..lineTo(p[3].dx, p[3].dy)
      ..close();
    final top = Path()
      ..moveTo(p[3].dx, p[3].dy)
      ..lineTo(p[2].dx, p[2].dy)
      ..lineTo(p[6].dx, p[6].dy)
      ..lineTo(p[7].dx, p[7].dy)
      ..close();
    final side = Path()
      ..moveTo(p[1].dx, p[1].dy)
      ..lineTo(p[5].dx, p[5].dy)
      ..lineTo(p[6].dx, p[6].dy)
      ..lineTo(p[2].dx, p[2].dy)
      ..close();

    canvas.drawPath(front, Paint()..color = color.withValues(alpha: 0.92));
    canvas.drawPath(top, Paint()..color = color.withValues(alpha: 0.58));
    canvas.drawPath(side, Paint()..color = color.withValues(alpha: 0.72));

    if (isRisk) {
      final outline = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = risk!.level == RiskLevel.danger ? 3.0 : 2.0;
      canvas.drawPath(front, outline);
      canvas.drawCircle(p[3], 5 + (1 - object.depth) * 5, outline);
    }
  }

  void _drawEgoVehicle(Canvas canvas, Size size, Offset Function(_Vec3) project) {
    final z = 2.1;
    const x = 0.0;
    const width = 1.65;
    const height = 0.62;
    final p0 = project(const _Vec3(x - width / 2, 0, z));
    final p1 = project(const _Vec3(x + width / 2, 0, z));
    final p2 = project(const _Vec3(x + width / 2, height, z));
    final p3 = project(const _Vec3(x - width / 2, height, z));

    final car = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(car, Paint()..color = AppTheme.primary);

    final windshield = Path()
      ..moveTo(p3.dx + (p2.dx - p3.dx) * 0.16, p3.dy)
      ..lineTo(p2.dx - (p2.dx - p3.dx) * 0.16, p2.dy)
      ..lineTo(p2.dx - (p2.dx - p3.dx) * 0.30, p2.dy - 10)
      ..lineTo(p3.dx + (p2.dx - p3.dx) * 0.30, p3.dy - 10)
      ..close();
    canvas.drawPath(windshield, Paint()..color = AppTheme.background.withValues(alpha: 0.85));
  }

  void _drawHud(Canvas canvas, Size size) {
    final objectCount = objects.length;
    final textPainter = TextPainter(
      text: TextSpan(
        text: '3D PERCEPTION  •  $objectCount OBJECT${objectCount == 1 ? '' : 'S'}',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.68),
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(18, size.height - 28));
  }

  @override
  bool shouldRepaint(covariant _RoadScene3DPainter oldDelegate) => true;
}
