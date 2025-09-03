import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/tools_page.dart';
import 'pages/dashboard_page.dart';   // <-- NEW
import 'utils/metrics.dart';

class BrightlyPocApp extends StatefulWidget {
  const BrightlyPocApp({super.key});

  @override
  State<BrightlyPocApp> createState() => _BrightlyPocAppState();
}

class _BrightlyPocAppState extends State<BrightlyPocApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Metrics.instance.showPerfOverlay,
      builder: (_, show, __) {
        return MaterialApp(
          title: 'Brightly POC',
          debugShowCheckedModeBanner: false,
          showPerformanceOverlay: show,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
            useMaterial3: true,
          ),
          home: Scaffold(
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.movie), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.analytics), label: 'Dashboard'), 
                NavigationDestination(icon: Icon(Icons.build), label: 'Tools'),
              ],
            ),
            body: const [
              HomePage(),
              DashboardPage(), 
              ToolsPage(),
            ][_index],
          ),
        );
      },
    );
  }
}