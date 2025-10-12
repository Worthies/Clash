import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';

class ProxiesPage extends StatelessWidget {
  const ProxiesPage({super.key});

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
                  Text(
                    'Proxy Mode: ${state.proxyMode}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Rule', label: Text('Rule')),
                      ButtonSegment(value: 'Global', label: Text('Global')),
                      ButtonSegment(value: 'Direct', label: Text('Direct')),
                    ],
                    selected: {state.proxyMode},
                    onSelectionChanged: (Set<String> selected) {
                      state.setProxyMode(selected.first);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.proxies.length,
                itemBuilder: (context, index) {
                  final proxy = state.proxies[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: Icon(
                        proxy.isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: proxy.isActive ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        proxy.name,
                        style: TextStyle(
                          fontWeight: proxy.isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text('Type: ${proxy.type}'),
                      trailing: proxy.delay > 0
                          ? Chip(
                              label: Text('${proxy.delay}ms'),
                              backgroundColor: proxy.delay < 100
                                  ? Colors.green.withOpacity(0.2)
                                  : proxy.delay < 200
                                      ? Colors.orange.withOpacity(0.2)
                                      : Colors.red.withOpacity(0.2),
                            )
                          : null,
                      onTap: () {
                        state.selectNode(proxy);
                      },
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
}
