import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';

class Metrics {
  Metrics._();
  static final Metrics instance = Metrics._();

  DateTime? appStartAt;
  DateTime? firstFrameAt;

  void logColdStartTTFF() {
    if (appStartAt != null && firstFrameAt != null) {
      final ms = firstFrameAt!.difference(appStartAt!).inMilliseconds;
      debugPrint('TTFF (cold start): ${ms}ms');
    }
  }

  final ValueNotifier<bool> showPerfOverlay = ValueNotifier(false);

  final List<FrameTiming> _collected = [];
  VoidCallback? _remover;

  void startFrameSampling() {
    _collected.clear();
    _remover?.call();
    _remover = _attachTimings((timings) => _collected.addAll(timings));
  }

  Map<String, dynamic> stopAndSummarize() {
    _remover?.call();
    _remover = null;

    if (_collected.isEmpty) {
      return {'frames': 0, 'fps': 0.0, 'buildP99Ms': 0.0, 'rasterP99Ms': 0.0};
    }

    final spanUs = _collected.last.timestampInMicroseconds(FramePhase.rasterFinish) -
        _collected.first.timestampInMicroseconds(FramePhase.buildStart);
    final spanSec = spanUs / 1e6;
    final fps = (_collected.length / spanSec).clamp(0, 240).toDouble();

    List<double> build = _collected
        .map((f) =>
            (f.timestampInMicroseconds(FramePhase.buildFinish) -
                    f.timestampInMicroseconds(FramePhase.buildStart)) /
            1000.0)
        .toList()
      ..sort();
    List<double> raster = _collected
        .map((f) =>
            (f.timestampInMicroseconds(FramePhase.rasterFinish) -
                    f.timestampInMicroseconds(FramePhase.rasterStart)) /
            1000.0)
        .toList()
      ..sort();

    double p(List<double> a, double q) {
      final i = max(0, (q * (a.length - 1)).round());
      return a[i];
    }

    return {
      'frames': _collected.length,
      'fps': double.parse(fps.toStringAsFixed(1)),
      'buildP99Ms': double.parse(p(build, 0.99).toStringAsFixed(1)),
      'rasterP99Ms': double.parse(p(raster, 0.99).toStringAsFixed(1)),
    };
  }

  VoidCallback _attachTimings(TimingsCallback cb) {
    PlatformDispatcher.instance.onReportTimings = (timings) => cb(timings);
    return () => PlatformDispatcher.instance.onReportTimings = null;
  }
}