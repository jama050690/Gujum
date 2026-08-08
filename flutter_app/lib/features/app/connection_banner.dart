import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../chat/chat_controller.dart';
import '../settings/settings_controller.dart';

/// Ekranning tepasidagi tarmoq holati chizig'i — Telegram'dagi kabi.
///
/// Ilgari ulanish holati faqat suhbatlar ro'yxatida, tarjima qilinmagan matn
/// bilan ko'rinardi. Xabar ketmay qolsa foydalanuvchi buni bilmasdi va
/// ilova "shunchaki ishlamayapti" bo'lib tuyulardi. Endi ulanish yo'qolganda
/// yuqorida chiziq chiqadi va ulanish tiklanganda o'zi yo'qoladi.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final settings = context.watch<SettingsController>();
    final status = chat.connectionStatus;

    if (status == ConnectionStatus.connected) return child;

    String t(String key) => AppStrings.text(settings.localeCode, key);
    final offline = status == ConnectionStatus.offline;
    final theme = Theme.of(context);

    return Column(
      children: [
        Material(
          color: offline
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!offline) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                  ] else ...[
                    Icon(Icons.cloud_off_rounded,
                        size: 16, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      offline ? t('connection_offline') : t('connection_connecting'),
                      style: TextStyle(
                        fontSize: 13,
                        color: offline
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
