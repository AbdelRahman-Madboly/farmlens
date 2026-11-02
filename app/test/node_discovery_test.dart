import 'dart:convert';
import 'dart:io';

import 'package:farmlens/services/node_discovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A stand-in for a phone network interface.
class FakeInterface implements NetworkInterface {
  FakeInterface(this.name, List<String> ips)
      : addresses = ips.map((ip) => InternetAddress(ip)).toList();

  @override
  final String name;
  @override
  final List<InternetAddress> addresses;
  @override
  int get index => 0;
}

String status({String id = 'FL-001', bool service = true}) => jsonEncode({
      if (service) 'service': 'farmlens',
      'node_id': id,
      'node_name': 'FarmLens Node',
      'camera_backend': 'picamera2',
      'simulated': false,
    });

/// A network where only [nodes] (host -> status body) answer.
MockClient network(Map<String, String> nodes) => MockClient((req) async {
      final body = nodes[req.url.host];
      if (body == null) throw const SocketException('unreachable');
      return http.Response(body, 200);
    });

void main() {
  test('subnetHosts covers private /24s, hotspot first, skips own address', () {
    final hosts = NodeDiscovery.subnetHosts([
      FakeInterface('rmnet_data0', ['100.64.3.9']), // carrier, not private
      FakeInterface('swlan0', ['192.168.43.1']), // the phone's hotspot
    ]);
    expect(hosts.length, 253);
    expect(hosts.first, '192.168.43.2');
    expect(hosts, isNot(contains('192.168.43.1')));
    expect(hosts.where((h) => h.startsWith('100.')), isEmpty);
  });

  test('isPrivateIPv4', () {
    expect(NodeDiscovery.isPrivateIPv4('10.1.2.3'), isTrue);
    expect(NodeDiscovery.isPrivateIPv4('172.20.0.1'), isTrue);
    expect(NodeDiscovery.isPrivateIPv4('192.168.1.5'), isTrue);
    expect(NodeDiscovery.isPrivateIPv4('172.32.0.1'), isFalse);
    expect(NodeDiscovery.isPrivateIPv4('8.8.8.8'), isFalse);
    expect(NodeDiscovery.isPrivateIPv4('nope'), isFalse);
  });

  test('probe accepts FarmLens nodes, old ones too, and nothing else', () async {
    final d = NodeDiscovery(
        client: network({
      'new.test': status(),
      'old.test': status(service: false),
      'other.test': jsonEncode({'hello': 'world'}),
    }));
    final node = await d.probe('new.test');
    expect(node!.nodeId, 'FL-001');
    expect(node.baseUrl, 'http://new.test:8000');
    expect(node.cameraBackend, 'picamera2');
    expect(await d.probe('old.test'), isNotNull);
    expect(await d.probe('other.test'), isNull);
    expect(await d.probe('missing.test'), isNull);
  });

  test('scan finds a node on the phone hotspot', () async {
    final found = <DiscoveredNode>[];
    var lastProgress = 0;
    final d = NodeDiscovery(
      client: network({'192.168.43.57': status()}),
      interfaces: () async => [FakeInterface('swlan0', ['192.168.43.1'])],
    );
    final nodes = await d.scan(
      onFound: found.add,
      onProgress: (checked, total) => lastProgress = checked,
    );
    expect(nodes.single.host, '192.168.43.57');
    expect(found.single.nodeId, 'FL-001');
    expect(lastProgress, 253);
  });

  test('scan reports a node once, by IP, when it answers by name too',
      () async {
    final d = NodeDiscovery(
      client: network({'farmlens.local': status(), '10.0.0.8': status()}),
      interfaces: () async => [FakeInterface('wlan0', ['10.0.0.20'])],
    );
    final nodes = await d.scan();
    expect(nodes.single.host, '10.0.0.8');
  });

  test('scan with stopAtFirst returns the preferred host without scanning',
      () async {
    var subnetAsked = false;
    final d = NodeDiscovery(
      client: network({'192.0.2.4': status()}),
      interfaces: () async {
        subnetAsked = true;
        return [];
      },
    );
    final nodes = await d.scan(
        preferredHosts: ['192.0.2.4', 'farmlens.local'], stopAtFirst: true);
    expect(nodes.single.host, '192.0.2.4');
    expect(subnetAsked, isFalse);
  });

  test('scan finds nothing on an empty network', () async {
    final d = NodeDiscovery(
      client: network({}),
      interfaces: () async => [FakeInterface('wlan0', ['192.168.1.10'])],
    );
    expect(await d.scan(), isEmpty);
  });
}
