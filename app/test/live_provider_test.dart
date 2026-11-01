import 'dart:convert';

import 'package:farmlens/models/live_data.dart';
import 'package:farmlens/providers/live_provider.dart';
import 'package:farmlens/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'models_test.dart' show nodeCycleJson;

/// A fake node whose next /api/live answer can be set by the test.
class FakeNode {
  http.Response Function() next = () => http.Response('{}', 200);
  int calls = 0;

  late final client = MockClient((req) async {
    calls++;
    return next();
  });

  void serve(Map<String, dynamic> json) =>
      next = () => http.Response(jsonEncode(json), 200);

  void fail() => next = () => http.Response('down', 503);
}

LiveData live({required String id, required bool alert}) =>
    LiveData.fromJson(nodeCycleJson(cycleId: id, alert: alert));

void main() {
  group('isNewAlert', () {
    test('only alerting cycles with a new id count', () {
      expect(isNewAlert(live(id: 'a', alert: true), ''), isTrue);
      expect(isNewAlert(live(id: 'a', alert: true), 'a'), isFalse);
      expect(isNewAlert(live(id: 'b', alert: false), 'a'), isFalse);
      expect(isNewAlert(live(id: '', alert: true), 'a'), isFalse);
    });
  });

  group('LiveProvider', () {
    late FakeNode node;
    late ApiService api;
    late LiveProvider provider;

    setUp(() {
      node = FakeNode();
      api = ApiService('http://node.test:8000', client: node.client);
      provider = LiveProvider();
    });

    tearDown(() => provider.dispose());

    test('stores the latest reading', () async {
      node.serve(nodeCycleJson(cycleId: 'c1', alert: false));
      await provider.poll(api);
      expect(provider.latest.cycleId, 'c1');
      expect(provider.alerts, isEmpty);
      expect(provider.isOffline, isFalse);
    });

    test('the same alert cycle polled twice is recorded once', () async {
      node.serve(nodeCycleJson(cycleId: 'c1', alert: true));
      await provider.poll(api);
      await provider.poll(api);
      expect(provider.alerts, hasLength(1));
      expect(provider.unreadAlertCount, 1);

      node.serve(nodeCycleJson(cycleId: 'c2', alert: true));
      await provider.poll(api);
      expect(provider.alerts.map((a) => a.id), ['c2', 'c1']);
      expect(provider.unreadAlertCount, 2);

      provider.markAlertsRead();
      expect(provider.unreadAlertCount, 0);
      expect(provider.alerts, hasLength(2));
    });

    test('goes offline after three failed polls and recovers', () async {
      node.fail();
      await provider.poll(api);
      await provider.poll(api);
      expect(provider.isOffline, isFalse);
      await provider.poll(api);
      expect(provider.isOffline, isTrue);

      node.serve(nodeCycleJson(cycleId: 'c9', alert: false));
      await provider.poll(api);
      expect(provider.isOffline, isFalse);
      expect(provider.latest.cycleId, 'c9');
    });

    test('keeps at most 200 alerts', () {
      for (var i = 0; i < 250; i++) {
        provider.handleLiveData(live(id: 'c$i', alert: true));
      }
      expect(provider.alerts, hasLength(200));
      expect(provider.alerts.first.id, 'c249');
    });

    test('startPolling polls immediately and on the timer', () async {
      final fast = LiveProvider(pollInterval: const Duration(milliseconds: 10));
      node.serve(nodeCycleJson(cycleId: 'c1', alert: false));
      fast.startPolling(api);
      expect(fast.isPolling, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      fast.stopPolling();
      expect(fast.isPolling, isFalse);
      final callsAtStop = node.calls;
      expect(callsAtStop, greaterThanOrEqualTo(3));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(node.calls, callsAtStop);
      fast.dispose();
    });
  });
}
