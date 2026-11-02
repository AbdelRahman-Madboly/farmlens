import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../services/mjpeg_stream.dart';
import '../theme.dart';

/// Live camera view. Plays the node's MJPEG stream (/api/stream) and falls
/// back to a snapshot every 5 s for nodes without one. The stream only runs
/// while the tab is [active] and the app is in the foreground, so it does not
/// use the hotspot's bandwidth in the background.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.active = true, this.frames});

  final bool active;

  /// Injected in tests in place of the network stream.
  final Stream<Uint8List> Function(Uri url)? frames;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

enum _FeedMode { stream, snapshot }

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _snapshotInterval = Duration(seconds: 5);
  static const _retryDelay = Duration(seconds: 3);

  _FeedMode _mode = _FeedMode.stream;
  StreamSubscription<Uint8List>? _sub;
  Timer? _retryTimer;
  Timer? _snapshotTimer;
  bool _foreground = true;

  Uint8List? _frame;
  DateTime? _lastFrameTime;
  int _streamFailures = 0;
  bool _gotFrameThisStream = false;

  // Frames per second, measured over the last second.
  int _framesThisSecond = 0;
  int _fps = 0;
  Timer? _fpsTimer;

  String _snapshotKey = '';

  bool get _shouldRun => widget.active && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _fps = _framesThisSecond;
        _framesThisSecond = 0;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(CameraScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  String get _baseUrl =>
      Provider.of<SettingsProvider>(context, listen: false).deviceBaseUrl;

  /// Starts or stops the feed to match [_shouldRun].
  void _sync() {
    if (!mounted) return;
    _stopFeed();
    if (!_shouldRun || _baseUrl.isEmpty) return;
    if (_mode == _FeedMode.stream) {
      _startStream();
    } else {
      _refreshSnapshot();
      _snapshotTimer =
          Timer.periodic(_snapshotInterval, (_) => _refreshSnapshot());
    }
  }

  void _startStream() {
    final url = Uri.parse('$_baseUrl/api/stream');
    final source = widget.frames?.call(url) ?? mjpegFrames(url);
    _gotFrameThisStream = false;
    _sub = source.listen(
      (frame) {
        if (!mounted) return;
        _streamFailures = 0;
        _gotFrameThisStream = true;
        _framesThisSecond++;
        setState(() {
          _frame = frame;
          _lastFrameTime = DateTime.now();
        });
      },
      onError: (_) => _onStreamEnded(),
      onDone: _onStreamEnded,
      cancelOnError: true,
    );
  }

  void _onStreamEnded() {
    _sub = null;
    if (!mounted || !_shouldRun) return;
    if (!_gotFrameThisStream) _streamFailures++;
    // Three failures in a row without a single frame: an older node with no
    // /api/stream. Use snapshots instead.
    if (_streamFailures >= 3) {
      setState(() => _mode = _FeedMode.snapshot);
      _sync();
      return;
    }
    setState(() {});
    _retryTimer = Timer(_retryDelay, _sync);
  }

  void _refreshSnapshot() {
    if (!mounted) return;
    setState(() =>
        _snapshotKey = DateTime.now().millisecondsSinceEpoch.toString());
  }

  void _stopFeed() {
    _sub?.cancel();
    _sub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
  }

  void _restart() {
    _streamFailures = 0;
    setState(() => _mode = _FeedMode.stream);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopFeed();
    _fpsTimer?.cancel();
    super.dispose();
  }

  bool get _live =>
      _lastFrameTime != null &&
      DateTime.now().difference(_lastFrameTime!) < const Duration(seconds: 10);

  @override
  Widget build(BuildContext context) {
    final baseUrl =
        Provider.of<SettingsProvider>(context, listen: false).deviceBaseUrl;
    final status = context.watch<ConnectionProvider>().nodeStatus;
    final nodeId = status?.nodeId.isNotEmpty == true ? status!.nodeId : 'Node';
    final backend = status?.cameraBackend ?? '';
    final streaming = _mode == _FeedMode.stream;

    final statusText = !_live
        ? '$nodeId · Connecting…'
        : streaming
            ? '$nodeId · Live stream'
            : '$nodeId · Snapshot view';
    final rightText = !_live
        ? ''
        : streaming
            ? '$_fps fps'
            : 'every 5 s';

    return Scaffold(
      backgroundColor: FarmLensColors.background,
      appBar: AppBar(
        backgroundColor: FarmLensColors.background,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.videocam_outlined, color: FarmLensColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Camera Feed',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: FarmLensColors.primary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: FarmLensColors.textSecondary),
            onPressed: _restart,
            tooltip: 'Reconnect',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status bar ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: FarmLensColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FarmLensColors.border, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _live
                          ? FarmLensColors.primary
                          : FarmLensColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    key: const Key('camera-status'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: FarmLensColors.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    rightText,
                    style: const TextStyle(
                        fontSize: 12, color: FarmLensColors.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Camera image ─────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: baseUrl.isEmpty
                    ? _NoConnection()
                    : !_shouldRun && _frame == null
                        ? const _Paused()
                        : streaming
                        ? (_frame == null
                            ? (_sub == null && _streamFailures > 0
                                ? _NoSignal()
                                : const _Loading())
                            : Image.memory(
                                _frame!,
                                key: const Key('camera-frame'),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ))
                        : _snapshotImage(baseUrl),
              ),
            ),

            const SizedBox(height: 12),

            // ── Info card ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: FarmLensColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FarmLensColors.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Camera Info',
                      style: TextStyle(
                          fontSize: 11, color: FarmLensColors.textSecondary)),
                  const SizedBox(height: 8),
                  _InfoRow(
                      label: 'Source',
                      value: streaming
                          ? 'Node /api/stream (live MJPEG)'
                          : 'Node /api/snapshot'),
                  _InfoRow(
                      label: 'Camera',
                      value: backend == 'mock'
                          ? 'Simulated frames, not a real camera'
                          : backend.isEmpty
                              ? '-'
                              : backend),
                  _InfoRow(
                    label: 'Last frame',
                    value: _lastFrameTime != null
                        ? '${DateTime.now().difference(_lastFrameTime!).inSeconds}s ago'
                        : '-',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _snapshotImage(String baseUrl) {
    return Image.network(
      '$baseUrl/api/snapshot?t=$_snapshotKey',
      key: ValueKey(_snapshotKey),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, _) {
        if (frame != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _lastFrameTime = DateTime.now());
          });
        }
        return child;
      },
      errorBuilder: (context, error, stack) => _NoSignal(),
    );
  }
}

class _Paused extends StatelessWidget {
  const _Paused();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Icon(Icons.pause_circle_outline, size: 48, color: Colors.white38),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: CircularProgressIndicator(
            color: FarmLensColors.primary, strokeWidth: 2),
      ),
    );
  }
}

// ─── No connection placeholder ────────────────────────────────────────────────

class _NoConnection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 48, color: Colors.white38),
            SizedBox(height: 12),
            Text('Not connected',
                style: TextStyle(fontSize: 14, color: Colors.white54)),
            SizedBox(height: 4),
            Text('Connect to the node first',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

// ─── No signal placeholder ────────────────────────────────────────────────────

class _NoSignal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 48, color: Colors.white38),
            SizedBox(height: 12),
            Text('No camera signal',
                style: TextStyle(fontSize: 14, color: Colors.white54)),
            SizedBox(height: 4),
            Text('Check the node is on, retrying…',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: FarmLensColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FarmLensColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}