import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';

class TrafficMonitor extends StatelessWidget {
  const TrafficMonitor({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClashState>(
      builder: (context, state, child) {
        final stats = state.trafficStats;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                context,
                stats.formatBytes(stats.upload),
                Icons.upload,
                Colors.blue,
              ),
              _buildStatItem(
                context,
                stats.formatBytes(stats.download),
                Icons.download,
                Colors.green,
              ),
              _buildStatItem(
                context,
                stats.formatBytes(stats.total),
                Icons.data_usage,
                Colors.orange,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
