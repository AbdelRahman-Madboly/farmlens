import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../constants.dart';

/// A FarmLens node that answered GET /api/status.
class DiscoveredNode {
  final String host;
  final int port;
  final String nodeId;
  final String nodeName;
  final String cameraBackend;
  final bool simulated;

  const DiscoveredNode({
    required this.host,
    required this.port,
    required this.nodeId,
    this.nodeName = '',
    this.cameraBackend = '',
    this.simulated = false,
  });

  String get baseUrl => 'http://$host:$port';

  bool get hostIsIp => InternetAddress.tryParse(host) != null;
}

/// Lists this phone's IPv4 addresses. Replaced in tests.
typedef AddressLister = Future<List<NetworkInterface>> Function();

Future<List<NetworkInterface>> _listInterfaces() => NetworkInterface.list(
    type: InternetAddressType.IPv4, includeLoopback: false);

/// Finds FarmLens nodes on the network the phone is on.
///
/// Works when the phone and the Pi share a Wi-Fi network, and when the Pi is
/// joined to the phone's own hotspot: the hotspot is one of the phone's
/// network interfaces, so its subnet is scanned too. Each address gets a
/// short GET /api/status; a node is any host whose answer identifies FarmLens.
class NodeDiscovery {
  NodeDiscovery({
    http.Client? client,
    AddressLister? interfaces,
    this.port = 8000,
    this.probeTimeout = const Duration(milliseconds: 1200),
    this.concurrency = 64,
  })  : _client = client,
        _interfaces = interfaces ?? _listInterfaces;

  final http.Client? _client;
  final AddressLister _interfaces;
  final int port;
  final Duration probeTimeout;
  final int concurrency;

  /// Asks one host whether it is a FarmLens node.
  Future<DiscoveredNode?> probe(String host, {http.Client? client}) async {
    final c = client ?? _client;
    if (c == null) {
      final own = _newClient();
      try {
        return await probe(host, client: own);
      } finally {
        own.close();
      }
    }
    try {
      final res = await c
          .get(Uri.parse('http://$host:$port/api/status'))
          .timeout(probeTimeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return null;
      // Nodes from v0.2 send "service"; older ones are known by node_id plus
      // the camera fields.
      final isFarmLens = body['service'] == 'farmlens' ||
          (body['node_id'] is String && body.containsKey('camera_backend'));
      if (!isFarmLens) return null;
      return DiscoveredNode(
        host: host,
        port: port,
        nodeId: body['node_id']?.toString() ?? '',
        nodeName: body['node_name']?.toString() ?? '',
        cameraBackend: body['camera_backend']?.toString() ?? '',
        simulated: body['simulated'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Every address to try on the phone's private IPv4 subnets (one /24 per
  /// interface), Wi-Fi and hotspot interfaces first. The phone's own address
  /// is left out.
  static List<String> subnetHosts(List<NetworkInterface> interfaces,
      {int maxSubnets = 4}) {
    bool isWifi(String name) =>
        RegExp(r'wlan|swlan|softap|ap\d|wifi|eth|en\d|br', caseSensitive: false)
            .hasMatch(name);
    final sorted = [...interfaces]
      ..sort((a, b) => (isWifi(a.name) ? 0 : 1) - (isWifi(b.name) ? 0 : 1));

    final seenPrefixes = <String>{};
    final own = <String>{};
    for (final i in sorted) {
      for (final a in i.addresses) {
        if (a.type != InternetAddressType.IPv4 || !isPrivateIPv4(a.address)) {
          continue;
        }
        own.add(a.address);
        final parts = a.address.split('.');
        seenPrefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }
    final hosts = <String>[];
    for (final prefix in seenPrefixes.take(maxSubnets)) {
      for (var n = 1; n <= 254; n++) {
        final ip = '$prefix.$n';
        if (!own.contains(ip)) hosts.add(ip);
      }
    }
    return hosts;
  }

  static bool isPrivateIPv4(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((x) => x == null)) return false;
    final a = p[0]!, b = p[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  /// Looks for nodes. [preferredHosts] (a saved address, farmlens.local) are
  /// asked first; then the phone's subnets are scanned. [onFound] fires for
  /// each new node, [onProgress] with (checked, total).
  ///
  /// The same node can answer by name and by IP; it is reported once, by IP
  /// when one is known, because an IP keeps working when name lookup does not.
  Future<List<DiscoveredNode>> scan({
    List<String> preferredHosts = const [FarmLensConstants.defaultHostname],
    void Function(DiscoveredNode node)? onFound,
    void Function(int checked, int total)? onProgress,
    bool stopAtFirst = false,
  }) async {
    final client = _client ?? _newClient();
    final found = <String, DiscoveredNode>{};
    var stop = false;

    void record(DiscoveredNode? node) {
      if (node == null) return;
      final key = node.nodeId.isEmpty ? node.host : node.nodeId;
      final existing = found[key];
      if (existing != null && (existing.hostIsIp || !node.hostIsIp)) return;
      found[key] = node;
      onFound?.call(node);
      if (stopAtFirst) stop = true;
    }

    try {
      final preferred = preferredHosts.where((h) => h.isNotEmpty).toSet();
      final results = await Future.wait(
          preferred.map((h) => probe(h, client: client)));
      results.forEach(record);
      if (stop) return found.values.toList();

      List<NetworkInterface> ifaces;
      try {
        ifaces = await _interfaces();
      } catch (_) {
        ifaces = const [];
      }
      final hosts = subnetHosts(ifaces)
          .where((h) => !preferred.contains(h))
          .toList();
      final total = hosts.length;
      var checked = 0;
      var next = 0;
      onProgress?.call(0, total);

      Future<void> worker() async {
        while (!stop && next < hosts.length) {
          final host = hosts[next++];
          record(await probe(host, client: client));
          checked++;
          onProgress?.call(checked, total);
        }
      }

      await Future.wait(List.generate(concurrency, (_) => worker()));
      return found.values.toList();
    } finally {
      if (_client == null) client.close();
    }
  }

  http.Client _newClient() =>
      IOClient(HttpClient()..connectionTimeout = probeTimeout);
}
