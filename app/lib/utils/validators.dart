// Form validators for the connection screen. Each returns an error message,
// or null when the value is valid.

/// Accepts dotted-decimal IPv4 addresses and plain hostnames.
String? validateHost(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Enter an IP address or hostname';
  }
  final v = value.trim();
  if (v.contains(' ')) return 'No spaces allowed';
  if (v.contains('/') || v.contains(':')) {
    return 'Enter only the address, without http:// or a port';
  }

  final parts = v.split('.');
  final allNumeric = parts.every((p) => RegExp(r'^\d+$').hasMatch(p));
  if (allNumeric) {
    if (parts.length != 4) return 'Enter a valid IPv4 address';
    for (final p in parts) {
      final n = int.parse(p);
      if (n > 255) return 'Enter a valid IPv4 address';
    }
    return null;
  }

  // Hostname: letters, digits, hyphens and dots, e.g. farmlens.local
  if (!RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9-]+)*$')
      .hasMatch(v)) {
    return 'Enter a valid hostname';
  }
  return null;
}

String? validatePort(String? value) {
  if (value == null || value.trim().isEmpty) return 'Enter a port';
  final n = int.tryParse(value.trim());
  if (n == null || n < 1 || n > 65535) return 'Valid port: 1 to 65535';
  return null;
}
