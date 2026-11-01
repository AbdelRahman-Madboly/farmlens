import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/live_data.dart';
import '../models/cycle_log.dart';
import '../services/api_service.dart';
import '../constants.dart';

/// True when [data] is a new cycle (not the one already seen) that raised
/// an alert. Polling every 5 s sees the same 30 s cycle several times, so
/// alerts are de-duplicated by cycle id.
bool isNewAlert(LiveData data, String lastCycleId) =>
    data.alert && data.cycleId.isNotEmpty && data.cycleId != lastCycleId;

class LiveProvider extends ChangeNotifier {
  LiveProvider({
    this.pollInterval =
        const Duration(seconds: FarmLensConstants.pollIntervalSeconds),
  });

  final Duration pollInterval;

  LiveData _latest = LiveData.empty();
  final List<CycleLog> _alerts = [];
  int _unreadAlertCount = 0;
  String _lastCycleId = '';
  Timer? _timer;
  int _consecutiveErrors = 0;
  bool _isOffline = false;

  LiveData get latest => _latest;
  List<CycleLog> get alerts => List.unmodifiable(_alerts);
  int get unreadAlertCount => _unreadAlertCount;
  bool get isOffline => _isOffline;
  bool get isPolling => _timer != null;

  void markAlertsRead() {
    _unreadAlertCount = 0;
    notifyListeners();
  }

  void startPolling(ApiService api) {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => poll(api));
    poll(api);
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// One poll of /api/live. Public so tests can drive it without a timer.
  Future<void> poll(ApiService api) async {
    final data = await api.getLive();
    if (data == null) {
      _consecutiveErrors++;
      if (_consecutiveErrors >= FarmLensConstants.offlineAfterFailures &&
          !_isOffline) {
        _isOffline = true;
        notifyListeners();
      }
    } else {
      _consecutiveErrors = 0;
      _isOffline = false;
      handleLiveData(data);
    }
  }

  @visibleForTesting
  void handleLiveData(LiveData d) {
    _latest = d;
    if (isNewAlert(d, _lastCycleId)) {
      _alerts.insert(0, CycleLog.fromLiveData(d));
      _unreadAlertCount++;
      if (_alerts.length > FarmLensConstants.maxAlerts) _alerts.removeLast();
    }
    if (d.cycleId.isNotEmpty) _lastCycleId = d.cycleId;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
