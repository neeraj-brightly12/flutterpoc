import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart' show rootBundle;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

enum ChartKind { bar, pie, line }

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  bool _loading = true;
  ChartKind _kind = ChartKind.bar;

  // Raw
  List<_Movie> _movies = [];

  // Derived (computed once after load)
  late Map<int, int> _countByYear; // year -> count
  late List<int> _yearsSorted;     // sorted unique years
  late int _minYear;
  late int _maxYear;

  // Animations
  late final AnimationController _lineAnim;
  late final AnimationController _pieAnim;
  late final CurvedAnimation _pieCurve;

  @override
  void initState() {
    super.initState();

    // Animated line
    _lineAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(() {
        if (_kind == ChartKind.line) setState(() {});
      });

    // Animated pie (smooth ease-out)
    _pieAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pieCurve = CurvedAnimation(
      parent: _pieAnim,
      curve: Curves.easeOutCubic,
    )..addListener(() {
        if (_kind == ChartKind.pie) setState(() {});
      });

    _loadData();
  }

  @override
  void dispose() {
    _lineAnim.dispose();
    _pieAnim.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final sw = Stopwatch()..start();
      final jsonStr = await rootBundle.loadString('assets/movies.json');
      final raw = jsonDecode(jsonStr) as List<dynamic>;
      // Map to strong model (int year)
      _movies = raw.map((e) {
        final m = e as Map<String, dynamic>;
        final year = int.tryParse(m['year']?.toString() ?? '') ?? 0;
        return _Movie(m['title']?.toString() ?? '', year);
      }).where((m) => m.year > 0).toList();

      // Derived
      _countByYear = <int, int>{};
      for (final m in _movies) {
        _countByYear[m.year] = (_countByYear[m.year] ?? 0) + 1;
      }
      _yearsSorted = _countByYear.keys.toList()..sort();
      _minYear = _yearsSorted.isEmpty ? 2000 : _yearsSorted.first;
      _maxYear = _yearsSorted.isEmpty ? 2000 : _yearsSorted.last;

      sw.stop();
      debugPrint('[DASHBOARD] Loaded ${_movies.length} rows in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[DASHBOARD] JSON load error: $e');
      _movies = [];
      _countByYear = {};
      _yearsSorted = [];
      _minYear = 2000;
      _maxYear = 2000;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _lineAnim.forward(from: 0); // prime the line chart anim
      }
    }
  }

  // PURE helper: no side effects, safe to call multiple times.
  int _chooseYearTickInterval(int minYear, int maxYear) {
    final span = max(1, maxYear - minYear);
    if (span <= 6) return 1;
    if (span <= 12) return 2;
    if (span <= 25) return 5;
    if (span <= 50) return 10;
    return 20;
  }

  // Common palette
  static const _palette = <Color>[
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
    Colors.cyan,
    Colors.amber,
    Colors.deepPurple,
  ];

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final swBuild = Stopwatch()..start();

    final topBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SegmentedButton<ChartKind>(
        segments: const [
          ButtonSegment(value: ChartKind.bar, label: Text('Bar')),
          ButtonSegment(value: ChartKind.pie, label: Text('Pie')),
          ButtonSegment(value: ChartKind.line, label: Text('Line')),
        ],
        selected: {_kind},
        onSelectionChanged: (s) {
          setState(() => _kind = s.first);
          if (_kind == ChartKind.line) {
            _lineAnim.forward(from: 0);
          } else if (_kind == ChartKind.pie) {
            _pieAnim.forward(from: 0); // animate pie every time tab selected
          }
        },
      ),
    );

    final chart = switch (_kind) {
      ChartKind.bar  => _buildBarChart(context),
      ChartKind.pie  => _buildPieChart(context),
      ChartKind.line => _buildLineChart(context),
    };

    swBuild.stop();
    debugPrint('[DASHBOARD] ${_kind.name} build/render took ${swBuild.elapsedMilliseconds}ms');

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          topBar,
          Padding(
            padding: const EdgeInsets.all(16),
            child: chart,
          ),
          // Small legend (for pie)
          if (_kind == ChartKind.pie) _buildLegend(),
        ],
      ),
    );
  }

  // ------------------- BAR (Year -> Count) -------------------
  Widget _buildBarChart(BuildContext context) {
    if (_countByYear.isEmpty) {
      return const Center(child: Text('No data'));
    }

    // X axis uses sequential index 0..N-1, bottom labels display the actual year.
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < _yearsSorted.length; i++) {
      final year = _yearsSorted[i];
      final count = (_countByYear[year] ?? 0).toDouble();
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: count,
              width: 18,
              color: _palette[i % _palette.length],
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        ),
      );
    }

    final maxCount = _countByYear.values.fold<int>(0, max).toDouble();
    final yTop = max(1, maxCount).toDouble();

    return RepaintBoundary(
      child: SizedBox(
        height: 320,
        child: BarChart(
          BarChartData(
            gridData: const FlGridData(show: true),
            borderData: FlBorderData(show: false),
            barGroups: groups,
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  reservedSize: 32,
                  showTitles: true,
                  interval: max(1, (yTop / 4).floor()).toDouble(),
                  getTitlesWidget: (v, meta) => Text(v.toInt().toString(),
                      style: const TextStyle(fontSize: 10)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (v, meta) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= _yearsSorted.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _yearsSorted[idx].toString(), // <- no ".0"
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
            ),
            minY: 0,
            maxY: yTop,
          ),
        ),
      ),
    );
  }

  // ------------------- PIE (Year shares, animated radius+fade) -------------------
  Widget _buildPieChart(BuildContext context) {
    if (_countByYear.isEmpty) {
      return const Center(child: Text('No data'));
    }

    final total = _countByYear.values.fold<int>(0, (a, b) => a + b);

    // Animate slice radius (20 → 70) and opacity (0.3 → 1.0)
    final t = _pieCurve.value; // 0..1 eased
    final radius = 20 + (70 - 20) * t;
    final alpha = (0.3 + 0.7 * t).clamp(0.0, 1.0);

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < _yearsSorted.length; i++) {
      final y = _yearsSorted[i];
      final c = _countByYear[y] ?? 0;
      if (c == 0) continue;

      final color = _palette[i % _palette.length].withOpacity(alpha);

      sections.add(
        PieChartSectionData(
          value: c.toDouble(),    // proportions stay correct
          color: color,
          radius: radius,         // grows smoothly
          title: '',              // clean slices; legend below
          showTitle: false,
        ),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        height: 320,
        child: PieChart(
          PieChartData(
            sections: sections,
            sectionsSpace: 0,
            // animate center hole slightly too (optional)
            centerSpaceRadius: 44 - 6 * t, // shrinks a bit while slices grow
            pieTouchData: PieTouchData(enabled: false),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    if (_yearsSorted.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _yearsSorted.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: _palette[i % _palette.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text('${_yearsSorted[i]} (${_countByYear[_yearsSorted[i]]})'),
              ],
            ),
        ],
      ),
    );
  }

  // ------------------- ANIMATED LINE (cumulative releases) -------------------
  Widget _buildLineChart(BuildContext context) {
    if (_yearsSorted.isEmpty) {
      return const Center(child: Text('No data'));
    }

    // Build cumulative count over years
    final points = <FlSpot>[];
    var cumul = 0;
    for (final y in _yearsSorted) {
      cumul += _countByYear[y] ?? 0;
      points.add(FlSpot(y.toDouble(), cumul.toDouble()));
    }

    // Animate the Y by a factor 0..1
    final t = _lineAnim.value;
    final animated = points
        .map((p) => FlSpot(p.x, p.y * t))
        .toList();

    final yMax = max(1.0, points.last.y);
    final intervalX = _chooseYearTickInterval(_minYear, _maxYear);

    return RepaintBoundary(
      child: SizedBox(
        height: 320,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: true),
            borderData: FlBorderData(show: false),
            minX: _minYear.toDouble(),
            maxX: _maxYear.toDouble(),
            minY: 0,
            maxY: yMax,
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  reservedSize: 32,
                  showTitles: true,
                  interval: max(1, (yMax / 4).floor()).toDouble(),
                  getTitlesWidget: (v, _) =>
                      Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  reservedSize: 28,
                  showTitles: true,
                  interval: intervalX.toDouble(),
                  getTitlesWidget: (v, _) =>
                      Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: animated,
                isCurved: true,
                barWidth: 3,
                color: Colors.indigo,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Simple value object
class _Movie {
  final String title;
  final int year;
  const _Movie(this.title, this.year);
}