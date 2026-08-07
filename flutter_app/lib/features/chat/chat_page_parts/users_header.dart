part of '../chat_page.dart';

class _UsersHeader extends StatefulWidget {
  const _UsersHeader({
    required this.settings,
    required this.currentUser,
    required this.widget.searchController,
    required this.widget.showArchived,
    required this.widget.onOpenSidebar,
    required this.widget.onBack,
    required this.onChanged,
    this.title,
  });

  final SettingsController settings;
  final SessionUser? currentUser;
  final TextEditingController widget.searchController;
  final bool widget.showArchived;
  final VoidCallback widget.onOpenSidebar;
  final VoidCallback widget.onBack;
  final ValueChanged<String> onChanged;
  final String? title;

  @override
  State<_UsersHeader> createState() => _UsersHeaderState();
}

class _UsersHeaderState extends State<_UsersHeader> {
  /// Telegram qidiruvni sarlavha o'rnida ochadi — alohida modal oyna emas.
  bool _searchOpen = false;

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
    final searchChipColor = widget.settings.isDarkMode
        ? const Color(0xFF223140)
        : const Color(0xFFEAF0F6);
    final searchTextColor = widget.settings.isDarkMode ? Colors.white : const Color(0xFF17212B);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.showArchived ? widget.onBack : widget.onOpenSidebar,
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
                    // Telegram uslubi: maydon sarlavha o'rnida, keng va
                    // yumaloq, ichida tozalash tugmasi bilan.
                    ? Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: searchChipColor,
                          borderRadius: BorderRadius.circular(21),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search_rounded, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: widget.searchController,
                                autofocus: true,
                                onChanged: widget.onChanged,
                                style: TextStyle(color: searchTextColor),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: AppStrings.text(
                                      widget.settings.localeCode, 'search'),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                widget.searchController.clear();
                                widget.onChanged('');
                                setState(() => _searchOpen = false);
                              },
                              child: const Icon(Icons.close_rounded, size: 20),
                            ),
                          ],
                        ),
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
                  onPressed: () => setState(() => _searchOpen = true),
                  icon: const Icon(Icons.search_rounded),
                  color: titleColor,
                ),
                IconButton(
                  onPressed: widget.onOpenSidebar,
                  icon: const Icon(Icons.more_vert_rounded),
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
