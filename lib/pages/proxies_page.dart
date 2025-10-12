import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';

class ProxiesPage extends StatelessWidget {
  const ProxiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClashState>(
      builder: (context, state, child) {
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text('Proxy Mode: ${state.proxyMode}', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    ElevatedButton.icon(
                      label: const Icon(Icons.speed),
                      onPressed: () async {
                        await state.runSpeedTestAll();
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Groups as a sliver list
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final group = state.groups[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ExpansionTile(
                    title: Text(group.name),
                    subtitle: Text('Type: ${group.type}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: LayoutBuilder(
                          builder: (context, innerConstraints) {
                            // aim for min 160px per member chip/card
                            const minW = 360.0;
                            final maxCols = (innerConstraints.maxWidth / minW).floor().clamp(1, 8);
                            final itemW = innerConstraints.maxWidth / maxCols;

                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final member in group.proxies)
                                  Builder(
                                    builder: (context) {
                                      // Find the actual proxy node for this member
                                      final proxy = state.proxies.where((p) => p.name == member).firstOrNull;

                                      return SizedBox(
                                        width: (itemW - 8),
                                        child: Card(
                                          color: group.selected == member ? Colors.green.shade50 : null,
                                          child: InkWell(
                                            onTap: () async {
                                              await state.setGroupSelection(group.name, member);
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        group.selected == member
                                                            ? Icons.radio_button_checked
                                                            : Icons.radio_button_unchecked,
                                                        color: group.selected == member ? Colors.green : Colors.grey,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          member,
                                                          style: TextStyle(
                                                            fontWeight: group.selected == member
                                                                ? FontWeight.bold
                                                                : FontWeight.normal,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  if (proxy != null) ...[
                                                    Text(proxy.type, style: Theme.of(context).textTheme.bodySmall),
                                                    Text(proxy.protocol ?? 'UDP', style: Theme.of(context).textTheme.bodySmall),
                                                    Text(
                                                      '${proxy.host}${proxy.port != null ? ':${proxy.port}' : ''}',
                                                      style: Theme.of(context).textTheme.bodySmall,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Text(
                                                          proxy.delay > 0
                                                              ? '${proxy.delay}ms'
                                                              : proxy.delay == -1
                                                              ? 'ERR'
                                                              : '-',
                                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                            color: proxy.delay > 0
                                                                ? Colors.green
                                                                : proxy.delay == -1
                                                                ? Colors.red
                                                                : Colors.grey,
                                                          ),
                                                        ),
                                                        if (state.isTesting(proxy))
                                                          const SizedBox(
                                                            width: 16,
                                                            height: 16,
                                                            child: CircularProgressIndicator(strokeWidth: 2),
                                                          )
                                                        else
                                                          IconButton(
                                                            icon: const Icon(Icons.speed, size: 18),
                                                            tooltip: 'Test speed',
                                                            onPressed: () async {
                                                              await state.runSpeedTest(proxy);
                                                            },
                                                            padding: EdgeInsets.zero,
                                                            constraints: const BoxConstraints(),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }, childCount: state.groups.length),
            ),
          ],
        );
      },
    );
  }
}
