import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/node_status.dart';
import '../services/api_service.dart';

enum DeviceConnectionState { disconnected, connecting, connected, error }

class ConnectionProvider extends ChangeNotifier {
  ConnectionProvider({http.Client? client}) : _client = client;

  final http.Client? _client;
  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  NodeStatus? _nodeStatus;
  String? _errorMessage;

  DeviceConnectionState get state => _state;
  NodeStatus? get nodeStatus => _nodeStatus;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _state == DeviceConnectionState.connected;

  Future<bool> connect(String baseUrl) async {
    _state = DeviceConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    final api = ApiService(baseUrl, client: _client);
    final status = await api.getStatus();

    if (status != null) {
      _nodeStatus = status;
      _state = DeviceConnectionState.connected;
      notifyListeners();
      return true;
    } else {
      _state = DeviceConnectionState.error;
      _errorMessage = 'Could not reach node at $baseUrl';
      notifyListeners();
      return false;
    }
  }

  void disconnect() {
    _state = DeviceConnectionState.disconnected;
    _nodeStatus = null;
    _errorMessage = null;
    notifyListeners();
  }

  void setError(String message) {
    _state = DeviceConnectionState.error;
    _errorMessage = message;
    notifyListeners();
  }
}