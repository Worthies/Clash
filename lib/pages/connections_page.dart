import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';

class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClashState>(
      builder: (context, state, child) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('Active Connections: ${state.connections.length}', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      state.clearConnections();
                    },
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.connections.isEmpty
                  ? const Center(child: Text('No active connections'))
                  : ListView.builder(
                      itemCount: state.connections.length,
                      itemBuilder: (context, index) {
                        final conn = state.connections[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ExpansionTile(
                            leading: Icon(
                              conn.network == 'TCP' ? Icons.swap_horiz : Icons.swap_vert,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            // title: Text(conn.host),
                            title: Text('${conn.type} • ${conn.network} → ${conn.host}'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInfoRow('Source', conn.source),
                                    _buildInfoRow('Destination', conn.destination),
                                    _buildInfoRow('Upload', _formatBytes(conn.upload)),
                                    _buildInfoRow('Download', _formatBytes(conn.download)),
                                    _buildInfoRow('Start Time', _formatTime(conn.startTime)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
