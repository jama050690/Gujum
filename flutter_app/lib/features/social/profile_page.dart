import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
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
  bool _uploadingAvatar = false;

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

    // Sahifa darhol ochiladi: nom, raqam, bio va username allaqachon
    // seansda bor. Tarmoq javobini kutib bo'sh ekran ko'rsatishning hojati
    // yo'q — kelgach ustiga yoziladi.
    _fullNameController.text = user.fullName ?? '';
    _usernameController.text = user.username;
    _phoneController.text = user.phone ?? '';
    _birthdayController.text = user.birthday ?? '';
    _bioController.text = user.bio ?? '';
    setState(() => _loading = false);

    try {
      // Ikkala so'rov birga ketadi. Avval ketma-ket edi va sahifa ikkala
      // javobni kutib turardi — ya'ni ochilish vaqti ikki barobar.
      final profile = await repository.fetchProfile(user.username);
      if (!mounted) {
        return;
      }
      _fullNameController.text = profile.fullName;
      _usernameController.text = profile.username;
      _phoneController.text = profile.phone;
      _birthdayController.text = profile.birthday;
      _bioController.text = profile.bio;
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Tug'ilgan kunni taqvimdan tanlash.
  ///
  /// Saqlanadigan format o'zgarmaydi (YYYY-MM-DD) — server va boshqa
  /// ekranlar aynan shuni kutadi.
  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_birthdayController.text.trim());
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      locale: Locale(context.read<SettingsController>().localeCode),
      // Tug'ilgan kun uchun kun to'ri emas, avval yil ro'yxati ochiladi —
      // 20-40 yil orqaga oyma-oy varaqlash shart emas. Taqvim ustidagi
      // tugma orqali qo'lda kiritishga ham o'tish mumkin.
      initialDatePickerMode: DatePickerMode.year,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (selected == null) return;
    final month = selected.month.toString().padLeft(2, '0');
    final day = selected.day.toString().padLeft(2, '0');
    setState(() {
      _birthdayController.text = '${selected.year}-$month-$day';
    });
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

  /// Ekran kengligidagi kvadrat profil rasmi.
  ///
  /// Bosilganda rasm almashtirish menyusi ochiladi — avval bu sahifada
  /// rasmni umuman o'zgartirib bo'lmasdi.
  Widget _buildAvatarHeader(
    BuildContext context,
    String imageUrl,
    String? displayName,
  ) {
    final width = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: _uploadingAvatar ? null : _pickAvatar,
      child: SizedBox(
        width: width,
        height: width, // kvadrat: kenglik bilan bir xil balandlik
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    _avatarPlaceholder(theme, displayName),
              )
            else
              _avatarPlaceholder(theme, displayName),
            // Pastdagi qorayish — kamera belgisi har qanday rasmda ko'rinsin.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withAlpha(120), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Material(
                color: theme.colorScheme.primary,
                shape: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _uploadingAvatar
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.photo_camera_rounded,
                          color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarPlaceholder(ThemeData theme, String? displayName) {
    final name = (displayName ?? '').trim();
    final letter = name.isEmpty ? 'G' : name.substring(0, 1).toUpperCase();
    return Container(
      color: theme.colorScheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 96,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  /// Galereya yoki kamera — tizim tanlagichi shu ikkisidan biri uchun
  /// ochiladi, shuning uchun avval manbani so'raymiz.
  Future<void> _pickAvatar() async {
    final settings = context.read<SettingsController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(t('chat_gallery')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(t('chat_photo')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        // Profil rasmi uchun original o'lcham keraksiz — yuklash tez bo'lsin.
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() => _uploadingAvatar = true);
      final path = await context.read<SocialRepository>().uploadAvatar(picked.path);
      if (!mounted) return;
      await context.read<AuthController>().updateAvatar(path);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
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
              padding: EdgeInsets.zero,
              children: [
                _buildAvatarHeader(context, imageUrl, auth.user?.displayName),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
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
                        // Tug'ilgan kun qo'lda emas, taqvimdan tanlanadi:
                        // format xatosi ham, uzun raqam terish ham qolmaydi.
                        TextField(
                          controller: _birthdayController,
                          readOnly: true,
                          onTap: _pickBirthday,
                          decoration: InputDecoration(
                            labelText: t('profile_birthday'),
                            suffixIcon: const Icon(Icons.calendar_today_rounded),
                          ),
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
                ),
              ],
            ),
    );
  }
}
