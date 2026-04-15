import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../models/social_models.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import 'community_room_page.dart';
import 'social_repository.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  List<CommunityItem> _groups = const [];
  List<CommunityItem> _channels = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = context.read<SocialRepository>();
    final user = context.read<AuthController>().user;
    if (user == null) {
      return;
    }

    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        repository.fetchGroups(user.username),
        repository.fetchChannels(user.username),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _groups = results[0] as List<CommunityItem>;
        _channels = results[1] as List<CommunityItem>;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createCommunity(CommunityType type) async {
    final repository = context.read<SocialRepository>();
    final auth = context.read<AuthController>();
    final settings = context.read<SettingsController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    bool allowDownload = false;
    bool saving = false;

    try {
      await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> submit() async {
              if (nameController.text.trim().isEmpty || auth.user == null) {
                return;
              }
              setState(() => saving = true);
              try {
                if (type == CommunityType.group) {
                  await repository.createGroup(
                    username: auth.user!.username,
                    name: nameController.text.trim(),
                    allowDownload: allowDownload,
                  );
                } else {
                  await repository.createChannel(
                    username: auth.user!.username,
                    name: nameController.text.trim(),
                    description: descriptionController.text.trim(),
                    allowDownload: allowDownload,
                  );
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              } finally {
                if (context.mounted) {
                  setState(() => saving = false);
                }
              }
            }

            return AlertDialog(
              title: Text(t(type == CommunityType.group ? 'create_group' : 'create_channel')),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: t('community_name')),
                    ),
                    if (type == CommunityType.channel) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        decoration: InputDecoration(labelText: t('community_description')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: allowDownload,
                      onChanged: (value) => setState(() => allowDownload = value),
                      title: Text(t('allow_download')),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: Text(t('cancel')),
                ),
                FilledButton(
                  onPressed: saving ? null : submit,
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(t('create')),
                ),
              ],
            );
          },
        );
      },
    );
    } catch (error) {
      _showError(error);
    }

    nameController.dispose();
    descriptionController.dispose();
    await _load();
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('communities')),
          bottom: TabBar(
            tabs: [
              Tab(text: t('groups')),
              Tab(text: t('channels')),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) {
            return FloatingActionButton.extended(
              onPressed: () {
                final tabIndex = DefaultTabController.of(context).index;
                _createCommunity(
                  tabIndex == 0 ? CommunityType.group : CommunityType.channel,
                );
              },
              icon: const Icon(Icons.add),
              label: Text(t('create')),
            );
          },
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _CommunityList(
                    items: _groups,
                    settings: settings,
                    emptyText: t('no_groups'),
                  ),
                  _CommunityList(
                    items: _channels,
                    settings: settings,
                    emptyText: t('no_channels'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CommunityList extends StatelessWidget {
  const _CommunityList({
    required this.items,
    required this.settings,
    required this.emptyText,
  });

  final List<CommunityItem> items;
  final SettingsController settings;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyText));
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final imageUrl = AppConfig.resolveMediaUrl(item.avatar, settings.baseUrl);
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
            child: imageUrl.isEmpty ? Text(item.name.substring(0, 1).toUpperCase()) : null,
          ),
          title: Text(item.name),
          subtitle: Text(
            '${item.peopleCount} ${AppStrings.text(settings.localeCode, item.type == CommunityType.group ? 'members' : 'subscribers')}',
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CommunityRoomPage(item: item),
              ),
            );
          },
        );
      },
    );
  }
}
