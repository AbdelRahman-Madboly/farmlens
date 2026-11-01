import 'dart:convert';

import 'package:farmlens/models/fusion_settings.dart';
import 'package:farmlens/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'models_test.dart' show nodeCycleJson;

const base = 'http://node.test:8000';

void main() {
  test('getLive parses a 200 response', () async {
    final client = MockClient((req) async {
      expect(req.url.toString(), '$base/api/live');
      return http.Response(jsonEncode(nodeCycleJson()), 200);
    });
    final live = await ApiService(base, client: client).getLive();
    expect(live, isNotNull);
    expect(live!.cycleId, 'FL-001-20260101-120000');
  });

  test('getLive returns null on non-200, bad JSON and exceptions', () async {
    final notFound = MockClient((_) async => http.Response('nope', 500));
    expect(await ApiService(base, client: notFound).getLive(), isNull);

    final badJson = MockClient((_) async => http.Response('{not json', 200));
    expect(await ApiService(base, client: badJson).getLive(), isNull);

    final listBody = MockClient((_) async => http.Response('[1,2]', 200));
    expect(await ApiService(base, client: listBody).getLive(), isNull);

    final throws = MockClient((_) async => throw http.ClientException('down'));
    expect(await ApiService(base, client: throws).getLive(), isNull);
  });

  test('getLive times out', () async {
    final slow = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return http.Response('{}', 200);
    });
    final api = ApiService(base,
        client: slow, timeout: const Duration(milliseconds: 20));
    expect(await api.getLive(), isNull);
  });

  test('getLogs passes the limit and parses entries', () async {
    final client = MockClient((req) async {
      expect(req.url.queryParameters['limit'], '5');
      return http.Response(
          jsonEncode({
            'count': 2,
            'logs': [nodeCycleJson(cycleId: 'a'), nodeCycleJson(cycleId: 'b')]
          }),
          200);
    });
    final logs = await ApiService(base, client: client).getLogs(limit: 5);
    expect(logs.map((c) => c.id), ['a', 'b']);
  });

  test('getLogs returns empty on a malformed body', () async {
    final client =
        MockClient((_) async => http.Response(jsonEncode({'logs': 3}), 200));
    expect(await ApiService(base, client: client).getLogs(), isEmpty);
  });

  test('getStatus and getSettings', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/status') {
        return http.Response(
            jsonEncode({'node_id': 'FL-001', 'mode': 'MOCK'}), 200);
      }
      return http.Response(
          jsonEncode({'w1': 0.5, 'w2': 0.5, 'theta': 0.6, 'crop_type': 'x'}),
          200);
    });
    final api = ApiService(base, client: client);
    expect((await api.getStatus())!.nodeId, 'FL-001');
    expect((await api.getSettings())!.theta, 0.6);
  });

  test('postSettings sends JSON and the API key when set', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final api = ApiService(base, client: client, apiKey: 'k-123');
    final ok = await api.postSettings(FusionSettings.defaults());
    expect(ok, isTrue);
    expect(sent.method, 'POST');
    expect(sent.headers['X-API-Key'], 'k-123');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(sent.body)['theta'], 0.5);
  });

  test('postSettings omits the header without a key and fails on 401',
      () async {
    final client = MockClient((req) async {
      expect(req.headers.containsKey('X-API-Key'), isFalse);
      return http.Response('{"detail":"Missing or invalid X-API-Key"}', 401);
    });
    expect(
        await ApiService(base, client: client)
            .postSettings(FusionSettings.defaults()),
        isFalse);
  });

  test('imageUrl', () {
    expect(ApiService(base).imageUrl('FL-001-x'), '$base/api/image/FL-001-x');
  });
}
