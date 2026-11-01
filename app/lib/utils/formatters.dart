import 'package:flutter/material.dart';
import '../theme.dart';

/// Converts snake_case detection class to human-readable format.
/// e.g. "Tomato_Late_blight" -> "Tomato: Late Blight"
///      "Tomato_healthy"     -> "Tomato: Healthy"
///      "none"               → "No Detection"
String formatDetectionClass(String cls) {
  if (cls.isEmpty || cls == 'none') return 'No Detection';
  final parts = cls.split('_');
  if (parts.length < 2) return cls;
  final crop = parts[0];
  final rest = parts
      .sublist(1)
      .map((w) => w.isEmpty
          ? ''
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
  return '$crop: $rest';
}

/// Returns true if the detection class represents a disease
/// (i.e. not healthy and not empty/none).
bool isDisease(String cls) =>
    cls.isNotEmpty && !cls.contains('healthy') && cls != 'none';

/// Returns the colour for a given Ccombined score:
/// < 0.4  → green (normal)
/// < 0.65 → amber (watch)
/// >= 0.65 → red (alert)
Color ccombinedColor(double v) {
  if (v < 0.4) return FarmLensColors.primary;
  if (v < 0.65) return FarmLensColors.amber;
  return FarmLensColors.alert;
}

/// Returns a human-readable "time ago" string for a Unix timestamp.
String timeAgo(int unixTs) {
  if (unixTs == 0) return 'never';
  final diff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - unixTs;
  if (diff < 0) return 'just now';
  if (diff < 60) return '${diff}s ago';
  if (diff < 3600) return '${diff ~/ 60}m ago';
  return '${diff ~/ 3600}h ago';
}

/// Formats a Unix timestamp to "MMM D, HH:mm:ss".
String formatDateTime(int unixTs) {
  if (unixTs == 0) return '-';
  final dt =
      DateTime.fromMillisecondsSinceEpoch(unixTs * 1000, isUtc: false);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, $h:$m:$s';
}

/// Formats a Unix timestamp to short date "MMM D".
String formatDate(int unixTs) {
  if (unixTs == 0) return '-';
  final dt =
      DateTime.fromMillisecondsSinceEpoch(unixTs * 1000, isUtc: false);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}';
}

/// Formats a Unix timestamp to "HH:mm".
String formatTime(int unixTs) {
  if (unixTs == 0) return '-';
  final dt =
      DateTime.fromMillisecondsSinceEpoch(unixTs * 1000, isUtc: false);
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}