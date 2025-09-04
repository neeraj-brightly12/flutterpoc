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

enum ChartKind { bar, pie }

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  bool _loading = true;
  ChartKind _kind = ChartKind.bar;

  // Raw data
  List<_Movie> _movies = [];

  // Derived data
  late Map<int, int> _countByYear; // year -> count
  late List<int> _yearsSorted;     // sorted unique years

  // Animation for Pie chart
  late final AnimationController _pieAnim;
  late final CurvedAnimation _pieCurve;

  @override
  void initState() {
    super.initState();

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
    _pieAnim.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final sw = Stopwatch()..start();
      final jsonStr = await rootBundle.loadString('assets/movies.json');
      final raw = jsonDecode(jsonStr) as List<dynamic>;

      _movies = raw.map((e) {
        final m = e as Map<String, dynamic>;
        final year = int.tryParse(m['year']?.toString() ?? '') ?? 0;
        return _Movie(m['title']?.toString() ?? '', year);
      }).where((m) => m.year > 0).toList();

      _countByYear = <int, int>{};
      for (final m in _movies) {
        _countByYear[m.year] = (_countByYear[m.year] ?? 0) + 1;
      }
      _yearsSorted = _countByYear.keys.toList()..sort();

      sw.stop();
      debugPrint('[DASHBOARD] Loaded ${_movies.length} rows in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[DASHBOARD] JSON load error: $e');
      _movies = [];
      _countByYear = {};
      _yearsSorted = [];
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // Palette
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

    final topBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SegmentedButton<ChartKind>(
        segments: const [
          ButtonSegment(value: ChartKind.bar, label: Text('Bar')),
          ButtonSegment(value: ChartKind.pie, label: Text('Pie')),
        ],
        selected: {_kind},
        onSelectionChanged: (s) {
          setState(() => _kind = s.first);
          if (_kind == ChartKind.pie) {
            _pieAnim.forward(from: 0); // animate pie each time selected
          }
        },
      ),
    );

    final chart = (_kind == ChartKind.bar)
        ? _buildBarChart(context)
        : _buildPieChart(context);

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

    return SizedBox(
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
                getTitlesWidget: (v, meta) =>
                    Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)),
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
                      _yearsSorted[idx].toString(),
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
    );
  }

  // ------------------- PIE (Year shares, animated) -------------------
  Widget _buildPieChart(BuildContext context) {
    if (_countByYear.isEmpty) {
      return const Center(child: Text('No data'));
    }

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
          value: c.toDouble(),
          color: color,
          radius: radius,
          showTitle: false,
        ),
      );
    }

    return SizedBox(
      height: 320,
      child: PieChart(
        PieChartData(
          sections: sections,
          sectionsSpace: 0,
          centerSpaceRadius: 44 - 6 * t,
          pieTouchData: PieTouchData(enabled: false),
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
}

// Simple model
class _Movie {
  final String title;
  final int year;
  const _Movie(this.title, this.year);
}