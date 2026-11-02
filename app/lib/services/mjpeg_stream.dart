import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Splits an MJPEG byte stream (multipart/x-mixed-replace, as served by the
/// node at /api/stream) into whole JPEG images.
///
/// It looks for the JPEG start (FF D8) and end (FF D9) markers and ignores the
/// multipart headers between them. The node encodes frames with OpenCV, which
/// writes no embedded thumbnail, so the first end marker after a start marker
/// always ends the frame.
class MjpegParser {
  MjpegParser({this.maxBufferBytes = 4 * 1024 * 1024});

  /// A frame larger than this is dropped, so a broken stream cannot grow the
  /// buffer without limit.
  final int maxBufferBytes;

  final BytesBuilder _pending = BytesBuilder(copy: false);

  /// Feeds [chunk] and returns every frame it completed, oldest first.
  List<Uint8List> add(List<int> chunk) {
    _pending.add(chunk);
    final buf = _pending.takeBytes();
    final frames = <Uint8List>[];

    var pos = 0;
    var keepFrom = buf.length;
    while (true) {
      final start = _find(buf, 0xD8, pos);
      if (start < 0) {
        // Keep a trailing FF: it may be the first half of the next marker.
        keepFrom = buf.isNotEmpty && buf.last == 0xFF ? buf.length - 1 : buf.length;
        break;
      }
      final end = _find(buf, 0xD9, start + 2);
      if (end < 0) {
        keepFrom = start;
        break;
      }
      frames.add(Uint8List.sublistView(buf, start, end + 2));
      pos = end + 2;
    }

    final rest = buf.length - keepFrom;
    if (rest > 0 && rest <= maxBufferBytes) {
      _pending.add(Uint8List.sublistView(buf, keepFrom));
    }
    return frames;
  }

  /// Index of the FF byte of the marker FF [second], at or after [from].
  static int _find(Uint8List buf, int second, int from) {
    for (var i = from; i < buf.length - 1; i++) {
      if (buf[i] == 0xFF && buf[i + 1] == second) return i;
    }
    return -1;
  }
}

/// Opens [url] and yields each JPEG frame of the MJPEG stream.
///
/// Cancelling the subscription closes the connection. Throws on a non-200
/// response or if no response arrives within [connectTimeout].
Stream<Uint8List> mjpegFrames(
  Uri url, {
  http.Client? client,
  Duration connectTimeout = const Duration(seconds: 8),
}) async* {
  final c = client ?? http.Client();
  try {
    final res = await c.send(http.Request('GET', url)).timeout(connectTimeout);
    if (res.statusCode != 200) {
      throw http.ClientException('Stream returned ${res.statusCode}', url);
    }
    final parser = MjpegParser();
    await for (final chunk in res.stream) {
      for (final frame in parser.add(chunk)) {
        yield frame;
      }
    }
  } finally {
    if (client == null) c.close();
  }
}
