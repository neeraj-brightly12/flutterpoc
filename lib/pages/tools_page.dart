import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../utils/metrics.dart';
import '../widgets/status_chip.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});
  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> with SingleTickerProviderStateMixin {
  String _fpsSummary = 'Not measured';
  String _ttff = '—';
  double _progress = 0.0;
  String _downloadSummary = 'No download yet';

  final _urlCtrl = TextEditingController(
    text:
        'https://upload.wikimedia.org/wikipedia/commons/3/3f/Fronalpstock_big.jpg',
  );

  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat();

    final a = Metrics.instance.appStartAt;
    final f = Metrics.instance.firstFrameAt;
    if (a != null && f != null) {
      _ttff = '${f.difference(a).inMilliseconds} ms';
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _measureFps() async {
    setState(() => _fpsSummary = 'Sampling 5s…');
    Metrics.instance.startFrameSampling();
    await Future.delayed(const Duration(seconds: 5));
    final m = Metrics.instance.stopAndSummarize();
    setState(() => _fpsSummary =
        'Frames: ${m['frames']}, FPS: ${m['fps']}, p99 build: ${m['buildP99Ms']}ms, p99 raster: ${m['rasterP99Ms']}ms');
  }

  Future<void> _download() async {
    setState(() {
      _progress = 0.0;
      _downloadSummary = 'Starting…';
    });

    try {
      final dio = Dio(BaseOptions(
        followRedirects: true,
        validateStatus: (s) => s != null && s < 500,
        receiveDataWhenStatusError: true,
      ));

      final tmp = await Directory.systemTemp.createTemp('dl-');
      final out = '${tmp.path}/big.bin';

      final sw = Stopwatch()..start();
      final resp = await dio.download(
        _urlCtrl.text.trim(),
        out,
        onReceiveProgress: (r, t) {
          if (t > 0) setState(() => _progress = r / t);
        },
      );
      sw.stop();

      if (resp.statusCode == 200) {
        final file = File(out);
        final bytes = await file.length();
        final mb = bytes / (1024 * 1024);
        final s = sw.elapsedMilliseconds / 1000.0;
        final mbps = s > 0 ? mb / s : 0;
        setState(() => _downloadSummary =
            'Saved: $out\nSize: ${mb.toStringAsFixed(2)} MB in ${s.toStringAsFixed(2)}s  (${mbps.toStringAsFixed(2)} MB/s)');
      } else {
        setState(() => _downloadSummary = 'HTTP ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _downloadSummary = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Tools'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 8), child: StatusChip()),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // SwitchListTile(
          //   title: const Text('Show Performance Overlay'),
          //   value: Metrics.instance.showPerfOverlay.value,
          //   onChanged: (v) => setState(() => Metrics.instance.showPerfOverlay.value = v),
          // ),
          ListTile(
            title: const Text('Cold start TTFF'),
            subtitle: Text(_ttff),
          ),
          const Divider(height: 32),
          // ListTile(
          //   title: const Text('FPS / Jank sampler (5 seconds)'),
          //   subtitle: Text(_fpsSummary),
          //   trailing: ElevatedButton(
          //     onPressed: _measureFps,
          //     child: const Text('Measure'),
          //   ),
          // ),
          // const SizedBox(height: 12),
          // Center(
          //   child: RotationTransition(
          //     turns: _spinCtrl,
          //     child: const Icon(Icons.sync, size: 48),
          //   ),
          // ),
          const Divider(height: 32),
          const Text('Big download (network test)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (_progress == 0 || _progress == 1) ? null : _progress),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download),
                label: const Text('Download'),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(_downloadSummary)),
            ],
          ),
        ],
      ),
    );
  }
}