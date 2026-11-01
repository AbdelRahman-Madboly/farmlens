import 'package:farmlens/models/cycle_log.dart';
import 'package:farmlens/models/fusion_settings.dart';
import 'package:farmlens/models/live_data.dart';
import 'package:farmlens/models/node_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cycle exactly as node/rpi/fusion.py compute() returns it.
Map<String, dynamic> nodeCycleJson({
  String cycleId = 'FL-001-20260101-120000',
  bool alert = true,
}) =>
    {
      'ts': 1767268800,
      'node_id': 'FL-001',
      'moisture_raw': 2480,
      'moisture_pct': 20.0,
      'water_raw': 1500,
      'water_pct': 60.0,
      'moisture_stress': 1,
      'water_stress': 0,
      'cs': 0.6,
      'cv': 0.72,
      'ccombined': 0.672,
      'alert': alert,
      'detection_class': 'Tomato_Late_blight',
      'detection_conf': 0.72,
      'cycle_id': cycleId,
      'has_image': true,
      'fault': 0,
      'sensor_source': 'mock',
    };

void main() {
  group('LiveData.fromJson', () {
    test('parses a node cycle', () {
      final d = LiveData.fromJson(nodeCycleJson());
      expect(d.nodeId, 'FL-001');
      expect(d.moisturePct, 20.0);
      expect(d.moistureStress, 1);
      expect(d.ccombined, closeTo(0.672, 1e-9));
      expect(d.alert, isTrue);
      expect(d.cycleId, 'FL-001-20260101-120000');
      expect(d.hasImage, isTrue);
      expect(d.sensorSource, 'mock');
    });

    test('tolerates strings, ints and missing fields', () {
      final d = LiveData.fromJson({
        'ts': '1700000000',
        'moisture_pct': '42.5',
        'water_pct': 40,
        'cv': null,
        'alert': 'true',
      });
      expect(d.ts, 1700000000);
      expect(d.moisturePct, 42.5);
      expect(d.waterPct, 40.0);
      expect(d.cv, 0.0);
      expect(d.alert, isTrue);
      expect(d.cycleId, '');
      expect(d.hasImage, isFalse);
    });

    test('garbage numbers fall back to zero', () {
      final d = LiveData.fromJson({'moisture_pct': 'wet', 'ts': 'soon'});
      expect(d.moisturePct, 0.0);
      expect(d.ts, 0);
    });
  });

  group('CycleLog', () {
    test('reads the id from cycle_id, as /api/logs sends it', () {
      final c = CycleLog.fromJson(nodeCycleJson(cycleId: 'FL-001-a'));
      expect(c.id, 'FL-001-a');
      expect(c.moistureStress, 1);
      expect(c.waterStress, 0);
      expect(c.hasImage, isTrue);
    });

    test('falls back to id for older mock servers', () {
      expect(CycleLog.fromJson({'id': 'legacy-1'}).id, 'legacy-1');
    });

    test('fromLiveData copies every field', () {
      final d = LiveData.fromJson(nodeCycleJson());
      final c = CycleLog.fromLiveData(d);
      expect(c.id, d.cycleId);
      expect(c.ccombined, d.ccombined);
      expect(c.detectionClass, d.detectionClass);
      expect(c.moistureStress, d.moistureStress);
    });

    test('toJson round-trips through fromJson', () {
      final c = CycleLog.fromJson(nodeCycleJson());
      final again = CycleLog.fromJson(c.toJson());
      expect(again.id, c.id);
      expect(again.ts, c.ts);
      expect(again.cv, c.cv);
      expect(again.alert, c.alert);
      expect(again.hasImage, c.hasImage);
    });
  });

  group('FusionSettings', () {
    test('defaults match the node defaults', () {
      final s = FusionSettings.defaults();
      expect(s.w1, 0.6);
      expect(s.w2, 0.4);
      expect(s.theta, 0.5);
      expect(s.cropType, 'tomato');
    });

    test('json round trip and copyWith', () {
      final s = FusionSettings.fromJson(
          {'w1': 0.7, 'w2': '0.3', 'theta': 0.4, 'crop_type': 'pepper'});
      expect(s.toJson(),
          {'w1': 0.7, 'w2': 0.3, 'theta': 0.4, 'crop_type': 'pepper'});
      final t = s.copyWith(theta: 0.9);
      expect(t.theta, 0.9);
      expect(t.w1, 0.7);
    });
  });

  group('NodeStatus', () {
    test('parses the node status payload', () {
      final s = NodeStatus.fromJson({
        'node_id': 'FL-001',
        'mode': 'MOCK',
        'ai_mode': 'mock',
        'sensor_mode': 'mock',
        'simulated': true,
        'uptime_s': 125,
        'cycle_count': 4,
        'esp32_connected': false,
        'camera_backend': 'mock',
        'auth_required': true,
      });
      expect(s.nodeId, 'FL-001');
      expect(s.simulated, isTrue);
      expect(s.authRequired, isTrue);
      expect(s.cycleCount, 4);
      expect(s.cameraBackend, 'mock');
    });

    test('infers simulated when an older node omits it', () {
      expect(NodeStatus.fromJson({'mode': 'MOCK'}).simulated, isTrue);
      expect(
          NodeStatus.fromJson({'mode': 'TFLITE', 'sensor_mode': 'esp32'})
              .simulated,
          isFalse);
    });
  });
}
