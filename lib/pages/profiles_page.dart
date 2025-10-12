import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_state.dart';
import '../models/clash_models.dart';

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({super.key});

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
                    'Profiles',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _showAddProfileDialog(context, state),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Profile'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.profiles.isEmpty
                  ? const Center(
                      child: Text('No profiles yet. Click + to add one.'),
                    )
                  : ListView.builder(
                      itemCount: state.profiles.length,
                      itemBuilder: (context, index) {
                        final profile = state.profiles[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: Icon(
                              profile.isActive ? Icons.check_circle : Icons.article,
                              color: profile.isActive ? Colors.green : Colors.grey,
                            ),
                            title: Text(profile.name),
                            subtitle: Text(
                              'Updated: ${_formatDate(profile.lastUpdate)}\n${profile.url}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                state.removeProfile(profile);
                              },
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

  void _showAddProfileDialog(BuildContext context, ClashState state) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Profile Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Subscription URL',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
                state.addProfile(Profile(
                  name: nameController.text,
                  url: urlController.text,
                  lastUpdate: DateTime.now(),
                ));
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
