import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';

class RulesPage extends StatelessWidget {
  const RulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClashState>(
      builder: (context, state, child) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Rules (${state.rules.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.rules.length,
                itemBuilder: (context, index) {
                  final rule = state.rules[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getRuleColor(rule.type).withOpacity(0.2),
                        child: Icon(
                          _getRuleIcon(rule.type),
                          color: _getRuleColor(rule.type),
                          size: 20,
                        ),
                      ),
                      title: Text(rule.type),
                      subtitle: Text(rule.payload),
                      trailing: Chip(
                        label: Text(rule.proxy),
                        backgroundColor: Colors.blue.withOpacity(0.1),
                      ),
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

  Color _getRuleColor(String type) {
    switch (type) {
      case 'DOMAIN-SUFFIX':
        return Colors.blue;
      case 'DOMAIN-KEYWORD':
        return Colors.green;
      case 'IP-CIDR':
        return Colors.orange;
      case 'GEOIP':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getRuleIcon(String type) {
    switch (type) {
      case 'DOMAIN-SUFFIX':
      case 'DOMAIN-KEYWORD':
        return Icons.language;
      case 'IP-CIDR':
      case 'GEOIP':
        return Icons.public;
      default:
        return Icons.rule;
    }
  }
}
