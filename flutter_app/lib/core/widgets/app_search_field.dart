import 'package:flutter/material.dart';

/// Ilovadagi yagona qidiruv maydoni.
///
/// Ilgari har bir ekran o'z qidiruv maydonini qaytadan yozardi (suhbat ichi,
/// chatlar ro'yxati, kontaktlar) — natijada bir xil funksiya har joyda boshqa
/// ko'rinishda va boshqa xatti-harakat bilan ishlardi. Endi hammasi shu
/// vidjetdan foydalanadi: Telegram uslubidagi yumaloq maydon, ichida qidiruv
/// belgisi va tozalash tugmasi.
///
/// Tozalash tugmasi matn bo'lsa uni tozalaydi, matn bo'sh bo'lsa qidiruvni
/// yopadi ([onClose]).
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClose,
    this.focusNode,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Qidiruvni yopish. null bo'lsa tozalash tugmasi faqat matnni tozalaydi.
  final VoidCallback? onClose;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  // Tozalash tugmasi matn bor-yo'qligiga qarab ko'rinadi.
  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _handleTrailingTap() {
    if (widget.controller.text.isNotEmpty) {
      widget.controller.clear();
      widget.onChanged?.call('');
      if (widget.onClose == null) return;
      return;
    }
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fillColor = isDark ? const Color(0xFF223140) : const Color(0xFFEFF3F6);
    final foreground = isDark ? Colors.white : const Color(0xFF1B2733);
    final hintColor = isDark ? Colors.white54 : Colors.black45;
    final hasText = widget.controller.text.isNotEmpty;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: foreground, fontSize: 16),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hintText,
                hintStyle: TextStyle(color: hintColor, fontSize: 16),
              ),
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
            ),
          ),
          if (hasText || widget.onClose != null)
            GestureDetector(
              onTap: _handleTrailingTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.close_rounded, size: 20, color: hintColor),
              ),
            ),
        ],
      ),
    );
  }
}
