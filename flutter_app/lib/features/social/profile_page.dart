import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../models/social_models.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import 'social_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthdayController = TextEditingController();
  final _bioController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<SimpleUser> _blockedUsers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _birthdayController.dispose();
    _bioController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final repository = context.read<SocialRepository>();
    final user = auth.user;
    if (user == null) {
      return;
    }

    setState(() => _loading = true);
    try {
      final profile = await repository.fetchProfile(user.username);
      final blocked = await repository.fetchBlockedUsers();
      if (!mounted) {
        return;
      }
      _fullNameController.text = profile.fullName;
      _usernameController.text = profile.username;
      _phoneController.text = profile.phone;
      _birthdayController.text = profile.birthday;
      _bioController.text = profile.bio;
      setState(() => _blockedUsers = blocked);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthController>();
    final settings = context.read<SettingsController>();
    final repository = context.read<SocialRepository>();

    setState(() => _saving = true);
    try {
      await repository.updateProfile(
        fullName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
        bio: _bioController.text.trim(),
        birthday: _birthdayController.text.trim(),
      );
      await auth.updateLocalProfile(
        fullName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
        bio: _bioController.text.trim(),
        birthday: _birthdayController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.text(settings.localeCode, 'save_profile'))),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _unblock(SimpleUser user) async {
    try {
      await context.read<SocialRepository>().unblockUser(user.username);
      if (!mounted) {
        return;
      }
      setState(() {
        _blockedUsers = _blockedUsers.where((item) => item.username != user.username).toList();
      });
    } catch (error) {
      _showError(error);
    }
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
    final auth = context.watch<AuthController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final imageUrl = AppConfig.resolveMediaUrl(auth.user?.avatar, settings.baseUrl);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('profile_my')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t('save')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                          child: imageUrl.isEmpty
                              ? Text((auth.user?.displayName ?? 'B').substring(0, 1).toUpperCase())
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _fullNameController,
                          decoration: InputDecoration(labelText: t('full_name')),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          enabled: false,
                          decoration: InputDecoration(labelText: t('username')),
                          controller: _usernameController,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneController,
                          decoration: InputDecoration(labelText: t('phone')),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _birthdayController,
                          decoration: const InputDecoration(labelText: 'YYYY-MM-DD'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _bioController,
                          maxLines: 3,
                          decoration: InputDecoration(labelText: t('settings_bio')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('blocked_users'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (_blockedUsers.isEmpty)
                          Text(t('no_blocked_users'))
                        else
                          ..._blockedUsers.map(
                            (user) {
                              final blockedImage = AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl);
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundImage:
                                      blockedImage.isNotEmpty ? NetworkImage(blockedImage) : null,
                                  child: blockedImage.isEmpty
                                      ? Text(user.username.substring(0, 1).toUpperCase())
                                      : null,
                                ),
                                title: Text(user.fullName),
                                subtitle: Text('@${user.username}'),
                                trailing: OutlinedButton(
                                  onPressed: () => _unblock(user),
                                  child: Text(t('unblock')),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
