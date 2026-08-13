import '../../../core/constants/app_constants.dart';
import '../models/tracked_object.dart';

enum RiskLevel { none, caution, warning, danger }

class RiskAssessment {
  const RiskAssessment({
    required this.level,
    required this.timeToCollisionSeconds,
    required this.object,
  });

  final RiskLevel level;
  final double? timeToCollisionSeconds;
  final TrackedObject object;
}

/// Turns per-frame tracked objects into a single actionable risk
/// assessment (the "Collision Prediction" + "Risk Assessment" stages of
/// the AI pipeline).
class CollisionPredictionService {
  RiskAssessment? assess(List<TrackedObject> objects) {
    RiskAssessment? worst;

    for (final obj in objects) {
      final ttc = obj.estimatedTimeToCollisionSeconds;
      final level = _levelFor(ttc, obj.closenessScore);
      if (level == RiskLevel.none) continue;

      if (worst == null || _rank(level) > _rank(worst.level)) {
        worst = RiskAssessment(
          level: level,
          timeToCollisionSeconds: ttc,
          object: obj,
        );
      }
    }

    return worst;
  }

  RiskLevel _levelFor(double? ttc, double closeness) {
    if (ttc == null) {
      // No closing-speed data yet; fall back to raw proximity.
      if (closeness > 0.55) return RiskLevel.caution;
      return RiskLevel.none;
    }
    if (ttc <= AppConstants.timeToCollisionDangerSeconds) return RiskLevel.danger;
    if (ttc <= AppConstants.timeToCollisionWarningSeconds) return RiskLevel.warning;
    if (closeness > 0.4) return RiskLevel.caution;
    return RiskLevel.none;
  }

  int _rank(RiskLevel l) => switch (l) {
        RiskLevel.none => 0,
        RiskLevel.caution => 1,
        RiskLevel.warning => 2,
        RiskLevel.danger => 3,
      };
}
