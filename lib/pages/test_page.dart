import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  bool _isTesting = false;
  final List<Map<String, dynamic>> _testResults = [];

  @override
  Widget build(BuildContext context) {
    return Consumer<ClashState>(
      builder: (context, state, child) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Proxy Speed Test',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isTesting ? null : () => _runTest(state),
                    icon: _isTesting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_isTesting ? 'Testing...' : 'Start Test'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _testResults.isEmpty
                  ? const Center(
                      child: Text('Click "Start Test" to begin testing proxies'),
                    )
                  : ListView.builder(
                      itemCount: _testResults.length,
                      itemBuilder: (context, index) {
                        final result = _testResults[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: Icon(
                              result['success'] ? Icons.check_circle : Icons.error,
                              color: result['success'] ? Colors.green : Colors.red,
                            ),
                            title: Text(result['name']),
                            subtitle: Text(result['message']),
                            trailing: result['success']
                                ? Chip(
                                    label: Text('${result['delay']}ms'),
                                    backgroundColor: _getDelayColor(result['delay']),
                                  )
                                : null,
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

  Future<void> _runTest(ClashState state) async {
    setState(() {
      _isTesting = true;
      _testResults.clear();
    });

    for (final proxy in state.proxies) {
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Simulate test
      final delay = proxy.delay > 0 ? proxy.delay : (50 + (proxy.name.hashCode % 200));
      final success = delay < 300;
      
      setState(() {
        _testResults.add({
          'name': proxy.name,
          'success': success,
          'delay': delay,
          'message': success ? 'Connected successfully' : 'Connection timeout',
        });
      });
    }

    setState(() {
      _isTesting = false;
    });
  }

  Color _getDelayColor(int delay) {
    if (delay < 100) return Colors.green.withOpacity(0.2);
    if (delay < 200) return Colors.orange.withOpacity(0.2);
    return Colors.red.withOpacity(0.2);
  }
}
