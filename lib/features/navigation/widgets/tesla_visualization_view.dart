import 'package:flutter/material.dart';

import '../../../core/themes/app_theme.dart';
import '../../ai/models/tracked_object.dart';
import '../../ai/services/collision_prediction_service.dart';
import '../../lane_detection/services/lane_detection_service.dart';

class TeslaVisualizationView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ScenePainter(
              trackedObjects: trackedObjects,
              risk: risk,
              laneReading: laneReading,
            ),
          ),
        ),
        if (speedKmh != null)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                children: [
                  Text(
                    speedKmh!.round().toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w200,
                    ),
                  ),
                  const Text(
                    'km/h',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.trackedObjects,
    required this.risk,
    required this.laneReading,
  });

  final List<TrackedObject> trackedObjects;
  final RiskAssessment? risk;
  final LaneReading? laneReading;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppTheme.background, Color.lerp(AppTheme.background, Colors.black, 0.4)!],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final vanishingPoint = Offset(size.width / 2, size.height * 0.32);
    final roadBottomY = size.height * 0.98;

    _drawRoad(canvas, size, vanishingPoint, roadBottomY);
    _drawLaneLines(canvas, size, vanishingPoint, roadBottomY);
    _drawEgoVehicle(canvas, size);
    for (final obj in trackedObjects) {
      _drawTrackedObject(canvas, size, vanishingPoint, roadBottomY, obj);
    }
  }

  void _drawRoad(Canvas canvas, Size size, Offset vp, double roadBottomY) {
    final roadWidthAtBottom = size.width * 0.9;
    final path = Path()
      ..moveTo(vp.dx - 4, vp.dy)
      ..lineTo(vp.dx + 4, vp.dy)
      ..lineTo(size.width / 2 + roadWidthAtBottom / 2, roadBottomY)
      ..lineTo(size.width / 2 - roadWidthAtBottom / 2, roadBottomY)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF1B222B));
  }

  void _drawLaneLines(Canvas canvas, Size size, Offset vp, double roadBottomY) {
    final leftNorm = laneReading?.leftLineX ?? 0.3;
    final rightNorm = laneReading?.rightLineX ?? 0.7;

    final leftBottomX = leftNorm * size.width;
    final rightBottomX = rightNorm * size.width;

    final paint = Paint()
      ..color = laneReading != null
          ? AppTheme.primary
          : AppTheme.textSecondary.withValues(alpha: 0.4)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(vp, Offset(leftBottomX, roadBottomY), paint);
    canvas.drawLine(vp, Offset(rightBottomX, roadBottomY), paint);

    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 2;
    const dashCount = 6;
    for (int i = 0; i < dashCount; i++) {
      final t0 = i / dashCount;
      final t1 = (i + 0.5) / dashCount;
      canvas.drawLine(
        Offset.lerp(vp, Offset(size.width / 2, roadBottomY), t0)!,
        Offset.lerp(vp, Offset(size.width / 2, roadBottomY), t1)!,
        dashPaint,
      );
    }
  }

  void _drawEgoVehicle(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height * 0.94;
    const w = 46.0, h = 66.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, bottom - h / 2), width: w, height: h),
      const Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = AppTheme.primary);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, bottom - h * 0.68), width: w * 0.6, height: h * 0.3),
        const Radius.circular(6),
      ),
      Paint()..color = AppTheme.background.withValues(alpha: 0.6),
    );
  }

  void _drawTrackedObject(
    Canvas canvas,
    Size size,
    Offset vp,
    double roadBottomY,
    TrackedObject obj,
  ) {
    final boxCenterXNorm =
        (obj.boundingBox.left + obj.boundingBox.width / 2) / obj.frameWidth;
    final depthT = (1.0 - obj.closenessScore).clamp(0.05, 0.95);

    final screenPos = Offset.lerp(
      Offset(size.width / 2 + (boxCenterXNorm - 0.5) * size.width * 0.9, roadBottomY),
      vp,
      depthT,
    )!;

    final scale = (1.0 - depthT).clamp(0.15, 1.0);
    final baseSize = obj.category == RoadObjectCategory.person ? 18.0 : 34.0;
    final w = baseSize * scale;
    final h = (obj.category == RoadObjectCategory.person ? 34.0 : 20.0) * scale;

    final isRiskObject = risk?.object.trackingId == obj.trackingId &&
        (risk?.level == RiskLevel.warning || risk?.level == RiskLevel.danger);
    final color = isRiskObject
        ? (risk!.level == RiskLevel.danger ? AppTheme.danger : AppTheme.warning)
        : (obj.category == RoadObjectCategory.person ? AppTheme.warning : AppTheme.textSecondary);

    final rect = Rect.fromCenter(center: screenPos, width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.2)),
      Paint()..color = color,
    );

    if (isRiskObject) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(4), Radius.circular(w * 0.25)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) {
    return oldDelegate.trackedObjects != trackedObjects ||
        oldDelegate.risk != risk ||
        oldDelegate.laneReading != laneReading;
  }
}
