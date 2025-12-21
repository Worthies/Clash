import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';
import '../models/clash_models.dart';

class RulesPage extends StatelessWidget {
  const RulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClashState>(
      builder: (context, state, child) {
        if (state.privateRulesEnabled && !state.privateRulesUnlocked) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Rules are private',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Enter password to view and edit rules.'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          _showUnlockDialog(context, state);
                        },
                        child: const Text('Unlock'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rules (${state.rules.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showAddRuleDialog(context, state),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Rule'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.rules.length,
                itemBuilder: (context, index) {
                  final rule = state.rules[index];
                  return Dismissible(
                    key: Key('rule-$index-${rule.type}-${rule.payload}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) {
                      state.removeRuleAt(index);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Rule deleted')),
                      );
                    },
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getRuleColor(
                            rule.type,
                          ).withValues(alpha: 0.2),
                          child: Icon(
                            _getRuleIcon(rule.type),
                            color: _getRuleColor(rule.type),
                            size: 20,
                          ),
                        ),
                        title: Text(rule.type),
                        subtitle: Text(rule.payload),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(
                                rule.proxy.isNotEmpty ? rule.proxy : '—',
                              ),
                              backgroundColor: Colors.blue.withValues(
                                alpha: 0.08,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _showEditRuleDialog(
                                context,
                                state,
                                index,
                                rule,
                              ),
                              icon: const Icon(Icons.edit, size: 18),
                            ),
                          ],
                        ),
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

  void _showAddRuleDialog(BuildContext context, ClashState state) {
    showDialog(
      context: context,
      builder: (context) {
        return _RuleDialog(state: state);
      },
    );
  }

  void _showEditRuleDialog(
    BuildContext context,
    ClashState state,
    int index,
    Rule rule,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return _RuleDialog(
          state: state,
          initialIndex: index,
          initialRule: rule,
        );
      },
    );
  }

  void _showUnlockDialog(BuildContext context, ClashState state) {
    final TextEditingController pwController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock Private Rules'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter password to unlock rules'),
            TextFormField(
              controller: pwController,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final ok = await state.unlockPrivateRules(pwController.text);
              if (ok) {
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Rules unlocked')),
                );
              } else {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Incorrect password')),
                );
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
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

class _RuleDialog extends StatefulWidget {
  final ClashState state;
  final int? initialIndex;
  final Rule? initialRule;

  const _RuleDialog({required this.state, this.initialIndex, this.initialRule});

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _type;
  late String _payload;
  late String _proxy;

  final _types = [
    'DOMAIN-SUFFIX',
    'DOMAIN-KEYWORD',
    'IP-CIDR',
    'GEOIP',
    'FINAL',
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialRule?.type ?? _types.first;
    _payload = widget.initialRule?.payload ?? '';
    _proxy =
        widget.initialRule?.proxy ??
        (widget.state.proxies.isNotEmpty
            ? widget.state.proxies.first.name
            : 'DIRECT');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialRule == null ? 'Add Rule' : 'Edit Rule'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
              decoration: const InputDecoration(labelText: 'Rule type'),
            ),
            TextFormField(
              initialValue: _payload,
              decoration: const InputDecoration(
                labelText: 'Payload (e.g. example.com)',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a payload' : null,
              onSaved: (v) => _payload = v!.trim(),
            ),
            DropdownButtonFormField<String>(
              initialValue: _proxy,
              items: const [
                DropdownMenuItem(value: 'DIRECT', child: Text('DIRECT')),
                DropdownMenuItem(value: 'PROXY', child: Text('PROXY')),
                DropdownMenuItem(value: 'BLOCK', child: Text('BLOCK')),
              ],
              onChanged: (v) => setState(() => _proxy = v ?? _proxy),
              decoration: const InputDecoration(labelText: 'Proxy'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _formKey.currentState!.save();
              final newRule = Rule(
                type: _type,
                payload: _payload,
                proxy: _proxy,
              );
              if (widget.initialIndex != null) {
                widget.state.updateRuleAt(widget.initialIndex!, newRule);
              } else {
                widget.state.addRule(newRule);
              }
              Navigator.of(context).pop();
            }
          },
          child: Text(widget.initialRule == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
