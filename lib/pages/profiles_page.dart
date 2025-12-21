import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/clash_state.dart';
import '../models/clash_models.dart';

class _ProfileViewDialog extends StatefulWidget {
  final Profile profile;

  const _ProfileViewDialog({required this.profile});

  @override
  State<_ProfileViewDialog> createState() => _ProfileViewDialogState();
}

class _ProfileViewDialogState extends State<_ProfileViewDialog> {
  late Future<String> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = _fetchProfileContent();
  }

  Future<String> _fetchProfileContent() async {
    try {
      final response = await http
          .get(Uri.parse(widget.profile.url))
          .timeout(const Duration(seconds: 10), onTimeout: () => throw TimeoutException('Request timed out'));

      if (response.statusCode == 200) {
        String content = response.body;
        // Try to decode if base64 encoded
        try {
          final decodedBytes = base64.decode(content);
          final decodedText = utf8.decode(decodedBytes);
          if (decodedText.trim().isNotEmpty) {
            content = decodedText;
          }
        } catch (_) {
          // Not base64 or decoding failed, use original
        }
        return content;
      } else {
        return 'Failed to fetch profile: HTTP ${response.statusCode}';
      }
    } on TimeoutException {
      return 'Request timed out after 10 seconds';
    } catch (e) {
      return 'Error fetching profile: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Profile Content'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Profile Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text(widget.profile.name, style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 8),
                const Text('URL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                SelectableText(widget.profile.url, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Content:', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: FutureBuilder<String>(
              future: _contentFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else if (snapshot.hasData) {
                  return SingleChildScrollView(
                    child: SelectableText(snapshot.data!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  );
                } else {
                  return const Center(child: Text('No content'));
                }
              },
            ),
          ),
        ],
      ),
      actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}

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
                  Text('Profiles', style: Theme.of(context).textTheme.titleLarge),
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
                  ? const Center(child: Text('No profiles yet. Click + to add one.'))
                  : ListView.builder(
                      itemCount: state.profiles.length,
                      itemBuilder: (context, index) {
                        final profile = state.profiles[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              profile.isActive ? Icons.check_circle : Icons.article,
                              color: profile.isActive ? Colors.green : Colors.grey,
                            ),
                            title: Text(profile.name),
                            subtitle: Text('Updated: ${_formatDate(profile.lastUpdate)}\n${profile.url}'),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showEditProfileDialog(context, state, profile);
                                } else if (value == 'view') {
                                  _showViewProfileDialog(context, profile);
                                } else if (value == 'delete') {
                                  // Defer profile removal until after build phase to avoid setState during build
                                  Future.microtask(() => state.removeProfile(profile));
                                }
                              },
                              itemBuilder: (BuildContext context) => [
                                const PopupMenuItem(
                                  value: 'view',
                                  child: Row(children: [Icon(Icons.visibility), SizedBox(width: 8), Text('View')]),
                                ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(children: [Icon(Icons.edit), SizedBox(width: 8), Text('Edit')]),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(children: [Icon(Icons.delete), SizedBox(width: 8), Text('Delete')]),
                                ),
                              ],
                            ),
                            onTap: () async {
                              final navigator = Navigator.of(context);
                              final messenger = ScaffoldMessenger.of(context);
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const Center(child: CircularProgressIndicator()),
                              );
                              await state.activateProfile(profile);
                              navigator.pop();
                              if (state.proxies.isNotEmpty) {
                                messenger.showSnackBar(SnackBar(content: Text('Profile "${profile.name}" activated')));
                              } else {
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Failed to activate profile "${profile.name}". See logs.')),
                                );
                              }
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
              decoration: const InputDecoration(labelText: 'Profile Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'Subscription URL', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
                state.addProfile(Profile(name: nameController.text, url: urlController.text, lastUpdate: DateTime.now()));
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, ClashState state, Profile profile) {
    final nameController = TextEditingController(text: profile.name);
    final urlController = TextEditingController(text: profile.url);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Profile Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'Subscription URL', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
                // Remove old profile
                state.removeProfile(profile);
                // Add updated profile
                state.addProfile(
                  Profile(
                    name: nameController.text,
                    url: urlController.text,
                    lastUpdate: DateTime.now(),
                    isActive: profile.isActive,
                  ),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showViewProfileDialog(BuildContext context, Profile profile) {
    showDialog(
      context: context,
      builder: (context) => _ProfileViewDialog(profile: profile),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
