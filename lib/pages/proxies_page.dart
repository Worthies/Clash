import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';
import '../widgets/emoji_text.dart';

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
                    title: ProxyNameWithEmoji(group.name, style: Theme.of(context).textTheme.titleMedium),
                    subtitle: Text('Type: ${group.type}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: LayoutBuilder(
                          builder: (context, innerConstraints) {
                            // Filter out proxies without host/port
                            final validMembers = group.proxies.where((member) {
                              final proxy = state.proxies.where((p) => p.name == member).firstOrNull;
                              return proxy != null && proxy.host != null && proxy.host!.isNotEmpty;
                            }).toList();

                            // aim for min 360px per card
                            const minW = 360.0;
                            final maxCols = (innerConstraints.maxWidth / minW).floor().clamp(1, 8);
                            final itemW = innerConstraints.maxWidth / maxCols;

                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final member in validMembers)
                                  Builder(
                                    builder: (context) {
                                      // Find the actual proxy node for this member
                                      // We know it exists because validMembers already filters valid ones
                                      final proxy = state.proxies.where((p) => p.name == member).firstOrNull;
                                      if (proxy == null) return const SizedBox.shrink();

                                      return SizedBox(
                                        width: (itemW - 8),
                                        child: Card(
                                          color: group.selected == member ? Colors.green.shade50 : null,
                                          child: InkWell(
                                            onTap: () async {
                                              await state.setGroupSelection(group.name, member);
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
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
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: ProxyNameWithEmoji(
                                                          member,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: group.selected == member
                                                                ? FontWeight.bold
                                                                : FontWeight.normal,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    '${proxy.type} • ${proxy.protocol ?? 'UDP'}${proxy.originalIndex >= 0 ? ' • #${proxy.originalIndex}' : ''}',
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                  Text(
                                                    '${proxy.host}${proxy.port != null ? ':${proxy.port}' : ''}',
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 1,
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
                                                          fontSize: 10,
                                                          color: proxy.delay > 0
                                                              ? Colors.green
                                                              : proxy.delay == -1
                                                              ? Colors.red
                                                              : Colors.grey,
                                                        ),
                                                      ),
                                                      if (state.isTesting(proxy))
                                                        const SizedBox(
                                                          width: 14,
                                                          height: 14,
                                                          child: CircularProgressIndicator(strokeWidth: 1.5),
                                                        )
                                                      else
                                                        GestureDetector(
                                                          onTap: () async {
                                                            await state.runSpeedTest(proxy);
                                                          },
                                                          child: const Icon(Icons.speed, size: 14),
                                                        ),
                                                    ],
                                                  ),
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
