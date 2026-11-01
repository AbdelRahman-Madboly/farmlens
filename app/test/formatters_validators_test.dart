import 'package:farmlens/theme.dart';
import 'package:farmlens/utils/formatters.dart';
import 'package:farmlens/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDetectionClass', () {
    test('formats node labels', () {
      expect(formatDetectionClass('Tomato_Late_blight'), 'Tomato: Late Blight');
      expect(formatDetectionClass('Tomato_healthy'), 'Tomato: Healthy');
      expect(formatDetectionClass('none'), 'No Detection');
      expect(formatDetectionClass(''), 'No Detection');
      expect(formatDetectionClass('Single'), 'Single');
    });
  });

  test('isDisease', () {
    expect(isDisease('Tomato_Late_blight'), isTrue);
    expect(isDisease('Tomato_healthy'), isFalse);
    expect(isDisease('none'), isFalse);
    expect(isDisease(''), isFalse);
  });

  test('ccombinedColor thresholds agree in both helpers', () {
    for (final v in [0.0, 0.39, 0.4, 0.64, 0.65, 1.0]) {
      expect(ccombinedColor(v), FarmLensColors.ccombinedColor(v), reason: '$v');
    }
    expect(ccombinedColor(0.39), FarmLensColors.primary);
    expect(ccombinedColor(0.4), FarmLensColors.amber);
    expect(ccombinedColor(0.65), FarmLensColors.alert);
  });

  test('timeAgo and date formatting handle zero', () {
    expect(timeAgo(0), 'never');
    expect(formatDateTime(0), '-');
    expect(formatTime(0), '-');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    expect(timeAgo(now - 30), '30s ago');
    expect(timeAgo(now - 120), '2m ago');
    expect(timeAgo(now + 100), 'just now');
  });

  group('validateHost', () {
    test('accepts IPv4 and hostnames', () {
      expect(validateHost('192.0.2.10'), isNull);
      expect(validateHost(' farmlens.local '), isNull);
      expect(validateHost('localhost'), isNull);
    });

    test('rejects bad input', () {
      expect(validateHost(''), isNotNull);
      expect(validateHost('300.1.1.1'), isNotNull);
      expect(validateHost('10.0.0'), isNotNull);
      expect(validateHost('my node'), isNotNull);
      expect(validateHost('http://192.0.2.10'), isNotNull);
      expect(validateHost('-bad-.local'), isNotNull);
    });
  });

  test('validatePort', () {
    expect(validatePort('8000'), isNull);
    expect(validatePort('0'), isNotNull);
    expect(validatePort('70000'), isNotNull);
    expect(validatePort('abc'), isNotNull);
    expect(validatePort(''), isNotNull);
  });
}
