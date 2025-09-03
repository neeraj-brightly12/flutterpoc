import 'package:flutter/material.dart';
import '../data/network_service.dart';

class StatusChip extends StatefulWidget {
  const StatusChip({super.key});
  @override
  State<StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<StatusChip> {
  bool _online = NetworkService.instance.isOnline;

  @override
  void initState() {
    super.initState();
    NetworkService.instance.onStatus.listen((v) {
      if (!mounted) return;
      setState(() => _online = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      avatar: Icon(
        _online ? Icons.wifi : Icons.wifi_off,
        size: 16,
        color: _online ? Colors.green : Colors.red,
      ),
      label: Text(_online ? 'Online' : 'Offline'),
    );
  }
}