import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fusion_settings.dart';
import '../services/api_service.dart';
import '../constants.dart';

class SettingsProvider extends ChangeNotifier {
  String _deviceBaseUrl = '';
  String _apiKey = '';
  bool _loaded = false;
  FusionSettings _fusionSettings = FusionSettings.defaults();

  String get deviceBaseUrl => _deviceBaseUrl;
  String get apiKey => _apiKey;
  bool get isLoaded => _loaded;
  FusionSettings get fusionSettings => _fusionSettings;
  bool get isConfigured => _deviceBaseUrl.isNotEmpty;

  /// An API client for the saved node, carrying the saved key.
  ApiService api() => ApiService(_deviceBaseUrl, apiKey: _apiKey);

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceBaseUrl = prefs.getString(FarmLensConstants.prefKeyBaseUrl) ?? '';
    _apiKey = prefs.getString(FarmLensConstants.prefKeyApiKey) ?? '';
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveDeviceUrl(String url, {String? apiKey}) async {
    _deviceBaseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(FarmLensConstants.prefKeyBaseUrl, url);
    if (apiKey != null) {
      _apiKey = apiKey;
      await prefs.setString(FarmLensConstants.prefKeyApiKey, apiKey);
    }
    notifyListeners();
  }

  Future<void> clearDeviceUrl() async {
    _deviceBaseUrl = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(FarmLensConstants.prefKeyBaseUrl);
    notifyListeners();
  }

  void updateFusionSettings(FusionSettings s) {
    _fusionSettings = s;
    notifyListeners();
  }
}
