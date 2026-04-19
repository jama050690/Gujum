part of '../chat_page.dart';

class _UsersHeader extends StatelessWidget {
  const _UsersHeader({
    required this.settings,
    required this.currentUser,
    required this.searchController,
    required this.showArchived,
    required this.onOpenSidebar,
    required this.onBack,
    required this.onChanged,
    this.title,
  });

  final SettingsController settings;
  final SessionUser? currentUser;
  final TextEditingController searchController;
  final bool showArchived;
  final VoidCallback onOpenSidebar;
  final VoidCallback onBack;
  final ValueChanged<String> onChanged;
  final String? title;

  Future<void> _openSearchSheet(BuildContext context) async {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1D2A39),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('search'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: searchController,
                autofocus: true,
                onChanged: onChanged,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: t('search'),
                  hintStyle: const TextStyle(color: Color(0xFF8FA3B6)),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            searchController.clear();
                            onChanged('');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: const Color(0xFF223140),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + 14;
    final avatarLabel = currentUser?.displayName ?? 'Bootchat';
    final avatarUrl = AppConfig.resolveMediaUrl(
      currentUser?.avatar,
      settings.baseUrl,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: showArchived ? onBack : onOpenSidebar,
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
                    child: showArchived
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
                child: Text(
                  showArchived ? (title ?? '') : 'Bootchat',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (!showArchived) ...[
                IconButton(
                  onPressed: () => _openSearchSheet(context),
                  icon: const Icon(Icons.search_rounded),
                  color: Colors.white,
                ),
                IconButton(
                  onPressed: onOpenSidebar,
                  icon: const Icon(Icons.more_vert_rounded),
                  color: Colors.white,
                ),
              ],
            ],
          ),
          if (!showArchived && searchController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF223140),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      searchController.text.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      searchController.clear();
                      onChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
