import 'json_utils.dart';

class LiveData {
  final int ts;
  final String nodeId;
  final int moistureRaw;
  final double moisturePct;
  final int waterRaw;
  final double waterPct;
  final int moistureStress;
  final int waterStress;
  final double cs;
  final double cv;
  final double ccombined;
  final bool alert;
  final String detectionClass;
  final double detectionConf;
  final String cycleId;
  final bool hasImage;
  final String sensorSource;

  const LiveData({
    required this.ts,
    required this.nodeId,
    required this.moistureRaw,
    required this.moisturePct,
    required this.waterRaw,
    required this.waterPct,
    required this.moistureStress,
    required this.waterStress,
    required this.cs,
    required this.cv,
    required this.ccombined,
    required this.alert,
    required this.detectionClass,
    required this.detectionConf,
    required this.cycleId,
    this.hasImage = false,
    this.sensorSource = '',
  });

  factory LiveData.fromJson(Map<String, dynamic> json) {
    return LiveData(
      ts: asInt(json['ts']),
      nodeId: json['node_id']?.toString() ?? '',
      moistureRaw: asInt(json['moisture_raw']),
      moisturePct: asDouble(json['moisture_pct']),
      waterRaw: asInt(json['water_raw']),
      waterPct: asDouble(json['water_pct']),
      moistureStress: asInt(json['moisture_stress']),
      waterStress: asInt(json['water_stress']),
      cs: asDouble(json['cs']),
      cv: asDouble(json['cv']),
      ccombined: asDouble(json['ccombined']),
      alert: asBool(json['alert']),
      detectionClass: json['detection_class']?.toString() ?? '',
      detectionConf: asDouble(json['detection_conf']),
      cycleId: json['cycle_id']?.toString() ?? '',
      hasImage: asBool(json['has_image']),
      sensorSource: json['sensor_source']?.toString() ?? '',
    );
  }

  factory LiveData.empty() {
    return const LiveData(
      ts: 0,
      nodeId: '',
      moistureRaw: 0,
      moisturePct: 0.0,
      waterRaw: 0,
      waterPct: 0.0,
      moistureStress: 0,
      waterStress: 0,
      cs: 0.0,
      cv: 0.0,
      ccombined: 0.0,
      alert: false,
      detectionClass: '',
      detectionConf: 0.0,
      cycleId: '',
    );
  }
}
