import 'json_utils.dart';

class NodeStatus {
  final String nodeId;

  /// Inference mode in upper case, for example "MOCK" or "TFLITE".
  final String mode;
  final String sensorMode;
  final String cameraBackend;
  final bool simulated;
  final bool esp32Connected;
  final bool authRequired;
  final int uptimeS;
  final int cycleCount;

  const NodeStatus({
    required this.nodeId,
    required this.mode,
    required this.sensorMode,
    required this.cameraBackend,
    required this.simulated,
    required this.esp32Connected,
    required this.authRequired,
    required this.uptimeS,
    required this.cycleCount,
  });

  factory NodeStatus.fromJson(Map<String, dynamic> json) {
    final mode = json['mode']?.toString() ?? '';
    final sensorMode = json['sensor_mode']?.toString() ?? '';
    return NodeStatus(
      nodeId: json['node_id']?.toString() ?? '',
      mode: mode,
      sensorMode: sensorMode,
      cameraBackend: json['camera_backend']?.toString() ?? '',
      // Older nodes do not send "simulated"; infer it from the modes.
      simulated: json.containsKey('simulated')
          ? asBool(json['simulated'])
          : mode.toUpperCase() == 'MOCK' || sensorMode == 'mock',
      esp32Connected: asBool(json['esp32_connected']),
      authRequired: asBool(json['auth_required']),
      uptimeS: asInt(json['uptime_s']),
      cycleCount: asInt(json['cycle_count']),
    );
  }
}
