import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClashState>(
      builder: (context, state, child) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'General Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // System Proxy
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('System Proxy'),
                    subtitle: Text(
                      state.systemProxy
                          ? 'Enabled: System using ${state.allowLan ? "0.0.0.0" : "127.0.0.1"}:${state.mixedPort}'
                          : 'Configure system to use this proxy server',
                    ),
                    value: state.systemProxy,
                    onChanged: (value) {
                      state.setSystemProxy(value);
                    },
                  ),
                  if (state.systemProxy)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'System proxy configured successfully',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Running applications may need to be restarted to use the proxy',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.secondary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Allow LAN
            Card(
              child: SwitchListTile(
                title: const Text('Allow LAN'),
                subtitle: Text(
                  state.allowLan
                      ? 'Listening on 0.0.0.0 (all interfaces)'
                      : 'Listening on 127.0.0.1 (localhost only)',
                ),
                value: state.allowLan,
                onChanged: (value) {
                  state.setAllowLan(value);
                },
              ),
            ),

            // Mixed Port
            Card(
              child: ListTile(
                title: const Text('Mixed Port'),
                subtitle: Text('Current port: ${state.mixedPort}'),
                trailing: const Icon(Icons.edit),
                onTap: () => _showPortDialog(context, state),
              ),
            ),

            const SizedBox(height: 24),
            Text('About', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.info),
                    title: Text('Version'),
                    subtitle: Text('1.0.0'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.code),
                    title: Text('Framework'),
                    subtitle: Text('Flutter 3.35.4 (Dart 3.9.2)'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description),
                    title: const Text('License'),
                    subtitle: const Text('MIT License'),
                    onTap: () {
                      showLicensePage(context: context);
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPortDialog(BuildContext context, ClashState state) {
    final controller = TextEditingController(text: state.mixedPort.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Mixed Port'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Port Number',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final port = int.tryParse(controller.text);
              if (port != null && port > 0 && port < 65536) {
                state.setMixedPort(port);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
