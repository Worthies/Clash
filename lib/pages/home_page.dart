import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';
import '../widgets/traffic_monitor.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClashState>(
      builder: (context, state, child) {
        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Traffic Monitor
                const TrafficMonitor(),
                const SizedBox(height: 20),

                // Current Profile
                _buildCard(
                  context,
                  'Current Profile',
                  state.profiles.isEmpty
                      ? 'No active profile'
                      : state.profiles.firstWhere((p) => p.isActive, orElse: () => state.profiles.first).name,
                  Icons.article,
                ),

                // Selected Node
                _buildCard(context, 'Selected Node', state.selectedNode?.name ?? 'DIRECT', Icons.router),

                // Proxy Mode
                _buildCard(context, 'Proxy Mode', state.proxyMode, Icons.security),

                // Network Settings
                _buildCard(
                  context,
                  'Network Settings',
                  'Listen: ${state.allowLan ? "0.0.0.0" : "127.0.0.1"}:${state.mixedPort} | Allow LAN: ${state.allowLan ? "Yes" : "No"}',
                  Icons.settings_ethernet,
                ),

                // IP Info
                _buildCard(context, 'IP Information', '${state.ipAddress} | ${state.country}', Icons.public),

                // System Info
                _buildCard(
                  context,
                  'System Info',
                  'System Proxy: ${state.systemProxy ? "Enabled" : "Disabled"} | Connections: ${state.connections.length}',
                  Icons.computer,
                ),
                const SizedBox(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, String title, String content, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(content),
      ),
    );
  }
}
