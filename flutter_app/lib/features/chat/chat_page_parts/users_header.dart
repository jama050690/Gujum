part of '../chat_page.dart';

class _UsersHeader extends StatefulWidget {
  const _UsersHeader({
    required this.settings,
    required this.currentUser,
    required this.searchController,
    required this.showArchived,
    required this.onBack,
    required this.onChanged,
    this.title,
  });

  final SettingsController settings;
  final SessionUser? currentUser;
  final TextEditingController searchController;
  final bool showArchived;
  final VoidCallback onBack;
  final ValueChanged<String> onChanged;
  final String? title;

  @override
  State<_UsersHeader> createState() => _UsersHeaderState();
}

class _UsersHeaderState extends State<_UsersHeader> {
  /// Telegram qidiruvni sarlavha o'rnida ochadi — alohida modal oyna emas.
  ///
  /// Bayroqning o'zi yetarli emas edi: u shu vidjetning holatida yashaydi,
  /// qidiruv matni va natijalar esa sahifada. Vidjet holati qaytadan
  /// yaratilsa (masalan, suhbat ochib qaytilganda) bayroq false bo'lib
  /// qolar, matn va natijalar esa joyida turardi — maydon yo'qolib,
  /// ro'yxat qidiruv natijalarida qotib qolardi. Endi matn bo'lsa,
  /// qidiruv har doim ochiq hisoblanadi.
  bool _explicitlyOpen = false;

  bool get _searchOpen =>
      _explicitlyOpen || widget.searchController.text.trim().isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tizimning "orqaga" tugmasi sahifada hal qilinadi, qidiruvning ochiq
    // ekani esa shu yerda. Matnni tozalash kifoya emas edi: bayroq shu
    // yerda qolib, maydon ochiq turaverardi. Sahifa shu ilgak orqali uni
    // ham yopadi.
    context.findAncestorStateOfType<_ChatPageState>()?.closeInboxSearch =
        _close;
  }

  bool _close() {
    final wasOpen = _searchOpen;
    widget.searchController.clear();
    widget.onChanged('');
    if (mounted) setState(() => _explicitlyOpen = false);
    return wasOpen;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + 14;
    final avatarLabel = widget.currentUser?.displayName ?? 'Gujum';
    final avatarUrl = AppConfig.resolveMediaUrl(
      widget.currentUser?.avatar,
      widget.settings.baseUrl,
    );
    final titleColor = widget.settings.isDarkMode
        ? Colors.white
        : const Color(0xFF2492E8);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                // Yon menyu olib tashlandi: rasmga bosilsa Profil bo'limi
                // ochiladi.
                onTap: widget.showArchived
                    ? widget.onBack
                    : () => HomeShellScope.of(context)
                        ?.selectTab(HomeTab.profile),
                child: Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF2EA6FF),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: widget.showArchived
                        ? const ColoredBox(
                            color: Color(0xFF223140),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                            ),
                          )
                        : _Avatar(
                            label: avatarLabel,
                            imageUrl: avatarUrl,
                            radius: 20,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _searchOpen && !widget.showArchived
                    // Telegram uslubi: maydon sarlavha o'rnida.
                    ? AppSearchField(
                        controller: widget.searchController,
                        // Faqat foydalanuvchi ochganda fokus olsin. Panel
                        // qaytadan qurilganda (suhbatdan qaytish) maydon
                        // matn tufayli ochiq bo'ladi va autofocus
                        // klaviaturani o'z-o'zidan ochib yuborardi.
                        autofocus: _explicitlyOpen,
                        hintText: AppStrings.text(
                            widget.settings.localeCode, 'search'),
                        onChanged: widget.onChanged,
                        onClose: _close,
                      )
                    : Text(
                        widget.showArchived ? (widget.title ?? '') : 'Gujum',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: titleColor,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
              ),
              if (!widget.showArchived && !_searchOpen) ...[
                IconButton(
                  onPressed: () => setState(() => _explicitlyOpen = true),
                  icon: const Icon(Icons.search_rounded),
                  color: titleColor,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
