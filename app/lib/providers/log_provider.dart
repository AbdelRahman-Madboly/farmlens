import 'package:flutter/foundation.dart';
import '../models/cycle_log.dart';
import '../services/api_service.dart';

class LogProvider extends ChangeNotifier {
  final List<CycleLog> _cycles = [];
  bool _isLoading = false;
  String? _error;

  List<CycleLog> get cycles => List.unmodifiable(_cycles);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadLogs(ApiService api) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final logs = await api.getLogs();
    _cycles
      ..clear()
      ..addAll(logs);
    _isLoading = false;
    notifyListeners();
  }

  CycleLog? byId(String id) => _cycles.where((c) => c.id == id).firstOrNull;

  void addCycle(CycleLog c) {
    _cycles.insert(0, c);
    if (_cycles.length > 200) _cycles.removeLast();
    notifyListeners();
  }
}