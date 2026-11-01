import 'json_utils.dart';
import 'live_data.dart';

class CycleLog {
  final String id;
  final int ts;
  final String nodeId;
  final double moisturePct;
  final double waterPct;
  final int moistureStress;
  final int waterStress;
  final double cs;
  final double cv;
  final double ccombined;
  final bool alert;
  final String detectionClass;
  final double detectionConf;
  final bool hasImage;

  const CycleLog({
    required this.id,
    required this.ts,
    required this.nodeId,
    required this.moisturePct,
    required this.waterPct,
    required this.cs,
    required this.cv,
    required this.ccombined,
    required this.alert,
    required this.detectionClass,
    required this.detectionConf,
    this.moistureStress = 0,
    this.waterStress = 0,
    this.hasImage = false,
  });

  /// Entries from GET /api/logs carry the cycle id as "cycle_id".
  /// "id" is accepted too, for older mock servers.
  factory CycleLog.fromJson(Map<String, dynamic> json) {
    return CycleLog(
      id: (json['cycle_id'] ?? json['id'])?.toString() ?? '',
      ts: asInt(json['ts']),
      nodeId: json['node_id']?.toString() ?? '',
      moisturePct: asDouble(json['moisture_pct']),
      waterPct: asDouble(json['water_pct']),
      moistureStress: asInt(json['moisture_stress']),
      waterStress: asInt(json['water_stress']),
      cs: asDouble(json['cs']),
      cv: asDouble(json['cv']),
      ccombined: asDouble(json['ccombined']),
      alert: asBool(json['alert']),
      detectionClass: json['detection_class']?.toString() ?? '',
      detectionConf: asDouble(json['detection_conf']),
      hasImage: asBool(json['has_image']),
    );
  }

  factory CycleLog.fromLiveData(LiveData d) {
    return CycleLog(
      id: d.cycleId,
      ts: d.ts,
      nodeId: d.nodeId,
      moisturePct: d.moisturePct,
      waterPct: d.waterPct,
      moistureStress: d.moistureStress,
      waterStress: d.waterStress,
      cs: d.cs,
      cv: d.cv,
      ccombined: d.ccombined,
      alert: d.alert,
      detectionClass: d.detectionClass,
      detectionConf: d.detectionConf,
      hasImage: d.hasImage,
    );
  }

  Map<String, dynamic> toJson() => {
        'cycle_id': id,
        'ts': ts,
        'node_id': nodeId,
        'moisture_pct': moisturePct,
        'water_pct': waterPct,
        'moisture_stress': moistureStress,
        'water_stress': waterStress,
        'cs': cs,
        'cv': cv,
        'ccombined': ccombined,
        'alert': alert,
        'detection_class': detectionClass,
        'detection_conf': detectionConf,
        'has_image': hasImage,
      };
}
