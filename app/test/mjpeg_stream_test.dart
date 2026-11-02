import 'dart:typed_data';

import 'package:farmlens/services/mjpeg_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake JPEG: start marker, [body], end marker.
List<int> jpeg(List<int> body) => [0xFF, 0xD8, ...body, 0xFF, 0xD9];

List<int> part(List<int> image) => [
      ...'--frame\r\nContent-Type: image/jpeg\r\n'
              'Content-Length: ${image.length}\r\n\r\n'
          .codeUnits,
      ...image,
      ...'\r\n'.codeUnits,
    ];

void main() {
  test('parser returns whole frames from one chunk', () {
    final a = jpeg([1, 2, 3]);
    final b = jpeg([4, 5]);
    final frames = MjpegParser().add([...part(a), ...part(b)]);
    expect(frames.map((f) => f.toList()), [a, b]);
  });

  test('parser joins frames split across chunks, even inside a marker', () {
    final a = jpeg([9, 8, 7, 6]);
    final bytes = [...part(a), ...part(jpeg([1]))];
    final parser = MjpegParser();
    final frames = <Uint8List>[];
    // Feed one byte at a time, which splits every marker in two.
    for (final byte in bytes) {
      frames.addAll(parser.add([byte]));
    }
    expect(frames.length, 2);
    expect(frames.first.toList(), a);
  });

  test('parser keeps nothing between frames', () {
    final parser = MjpegParser();
    expect(parser.add('--frame\r\nheaders\r\n\r\n'.codeUnits), isEmpty);
    expect(parser.add(jpeg([5])).single.toList(), jpeg([5]));
  });

  test('parser drops a frame larger than the buffer limit', () {
    final parser = MjpegParser(maxBufferBytes: 10);
    expect(parser.add([0xFF, 0xD8, ...List.filled(50, 1)]), isEmpty);
    // The oversize partial frame was dropped, the next one comes through.
    expect(parser.add(jpeg([2])).single.toList(), jpeg([2]));
  });

  test('mjpegFrames yields frames from an HTTP stream', () async {
    final client = MockClient.streaming((req, _) async {
      expect(req.url.path, '/api/stream');
      final body = [...part(jpeg([1])), ...part(jpeg([2])), ...part(jpeg([3]))];
      return http.StreamedResponse(
          Stream.fromIterable([body.sublist(0, 7), body.sublist(7)]), 200);
    });
    final frames = await mjpegFrames(Uri.parse('http://n.test:8000/api/stream'),
            client: client)
        .toList();
    expect(frames.map((f) => f.toList()), [jpeg([1]), jpeg([2]), jpeg([3])]);
  });

  test('mjpegFrames throws on a non-200 response', () async {
    final client = MockClient.streaming(
        (_, __) async => http.StreamedResponse(const Stream.empty(), 404));
    expect(
        mjpegFrames(Uri.parse('http://n.test/api/stream'), client: client)
            .toList(),
        throwsA(isA<http.ClientException>()));
  });
}
