import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/live_data.dart';
import '../models/cycle_log.dart';
import '../models/node_status.dart';
import '../models/fusion_settings.dart';
import '../constants.dart';

/// Thin client for the node REST API (node/rpi/api.py).
///
/// Every call returns null / empty / false on any network or parse error, so
/// callers only have to handle "no data". Pass [client] in tests to stub HTTP.
/// [apiKey] is sent as X-API-Key on write requests when it is not empty.
class ApiService {
  final String baseUrl;
  final String apiKey;
  final http.Client _client;
  final Duration _timeout;

  ApiService(
    this.baseUrl, {
    http.Client? client,
    this.apiKey = '',
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        _timeout = timeout ??
            const Duration(seconds: FarmLensConstants.apiTimeoutSeconds);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  String imageUrl(String cycleId) => '$baseUrl/api/image/$cycleId';

  Future<Map<String, dynamic>?> _getJson(String path) async {
    try {
      final res = await _client.get(_uri(path)).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      return body is Map<String, dynamic> ? body : null;
    } catch (_) {
      return null;
    }
  }

  Future<NodeStatus?> getStatus() async {
    final json = await _getJson('/api/status');
    return json == null ? null : NodeStatus.fromJson(json);
  }

  Future<LiveData?> getLive() async {
    final json = await _getJson('/api/live');
    return json == null ? null : LiveData.fromJson(json);
  }

  Future<List<CycleLog>> getLogs({int limit = 50}) async {
    final json = await _getJson('/api/logs?limit=$limit');
    final logs = json?['logs'];
    if (logs is! List) return [];
    return logs
        .whereType<Map<String, dynamic>>()
        .map(CycleLog.fromJson)
        .toList();
  }

  Future<FusionSettings?> getSettings() async {
    final json = await _getJson('/api/settings');
    return json == null ? null : FusionSettings.fromJson(json);
  }

  Future<bool> postSettings(FusionSettings s) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (apiKey.isNotEmpty) headers['X-API-Key'] = apiKey;
      final res = await _client
          .post(_uri('/api/settings'),
              headers: headers, body: jsonEncode(s.toJson()))
          .timeout(_timeout);
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body);
      return body is Map && body['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
