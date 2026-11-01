class FarmLensConstants {
  FarmLensConstants._();

  /// Port the node's FastAPI server listens on (node/rpi, API_PORT).
  static const String defaultDevicePort = '8000';
  static const String nodeId = 'FL-001';
  static const int pollIntervalSeconds = 5;
  static const int apiTimeoutSeconds = 8;

  /// Offline is declared after this many failed polls in a row.
  static const int offlineAfterFailures = 3;

  /// Maximum alerts kept in memory.
  static const int maxAlerts = 200;

  static const String prefKeyBaseUrl = 'device_base_url';
  static const String prefKeyRecentUrls = 'recent_urls';
  static const String prefKeyApiKey = 'device_api_key';
}
