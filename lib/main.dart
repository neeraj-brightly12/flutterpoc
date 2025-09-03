import 'package:flutter/material.dart';
import 'app.dart';
import 'data/db_service.dart';
import 'data/network_service.dart';
import 'utils/metrics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TTFF start
  Metrics.instance.appStartAt = DateTime.now();

  await DBService.instance.init();
  await NetworkService.instance.init();

  // TTFF end
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Metrics.instance.firstFrameAt = DateTime.now();
    Metrics.instance.logColdStartTTFF();
  });

  runApp(const BrightlyPocApp());
}