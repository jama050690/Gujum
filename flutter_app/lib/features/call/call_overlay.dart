import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';
import 'call_controller.dart';

class CallOverlayHost extends StatefulWidget {
  const CallOverlayHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<CallOverlayHost> createState() => _CallOverlayHostState();
}

class _CallOverlayHostState extends State<CallOverlayHost> {
  CallController? _controller;
  int _lastErrorVersion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = context.read<CallController?>();
    if (!identical(_controller, nextController)) {
      _controller?.removeListener(_handleControllerChanged);
      _controller = nextController;
      _controller?.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }

    final controller = _controller;
    if (controller == null ||
        controller.errorKey == null ||
        controller.errorVersion == _lastErrorVersion) {
      return;
    }

    _lastErrorVersion = controller.errorVersion;
    final settings = context.read<SettingsController>();
    final message = AppStrings.text(settings.localeCode, controller.errorKey!);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CallController?>();
    if (controller == null) {
      return widget.child;
    }

    return PopScope(
      canPop: !controller.hasSession && !controller.hasIncomingCall,
      child: Stack(
        children: [
          widget.child,
          if (controller.hasIncomingCall)
            Positioned.fill(
              child: _IncomingCallSheet(callController: controller),
            ),
          if (controller.hasSession)
            Positioned.fill(
              child: _ActiveCallSheet(callController: controller),
            ),
        ],
      ),
    );
  }
}

class _IncomingCallSheet extends StatelessWidget {
  const _IncomingCallSheet({
    required this.callController,
  });

  final CallController callController;

  @override
  Widget build(BuildContext context) {
    final incoming = callController.incomingCall;
    final settings = context.watch<SettingsController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);
    if (incoming == null) {
      return const SizedBox.shrink();
    }

    final avatarUrl =
        AppConfig.resolveMediaUrl(incoming.caller.avatar, settings.baseUrl);

    return ColoredBox(
      color: Colors.black.withAlpha(180),
      child: SafeArea(
        child: Center(
          child: Container(
            width: 340,
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: settings.isDarkMode
                  ? const Color(0xFF16202A)
                  : const Color(0xFFF7FAFD),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(45),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CallAvatar(
                  label: incoming.caller.displayName,
                  imageUrl: avatarUrl,
                  radius: 46,
                ),
                const SizedBox(height: 18),
                Text(
                  incoming.caller.displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${t('call_incoming')} - ${t(incoming.isVideo ? 'call_video' : 'call_audio')}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: settings.isDarkMode
                            ? Colors.white70
                            : Colors.black54,
                      ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundActionButton(
                      icon: Icons.call_end_rounded,
                      backgroundColor: const Color(0xFFE35555),
                      onPressed: callController.rejectIncomingCall,
                    ),
                    const SizedBox(width: 24),
                    _RoundActionButton(
                      icon: incoming.isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      backgroundColor: const Color(0xFF39A96B),
                      onPressed: () {
                        unawaited(callController.acceptIncomingCall());
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveCallSheet extends StatefulWidget {
  const _ActiveCallSheet({
    required this.callController,
  });

  final CallController callController;

  @override
  State<_ActiveCallSheet> createState() => _ActiveCallSheetState();
}

class _ActiveCallSheetState extends State<_ActiveCallSheet> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  Timer? _ticker;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderers();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _ActiveCallSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready) {
      _localRenderer.srcObject = widget.callController.localStream;
      _remoteRenderer.srcObject = widget.callController.remoteStream;
    }
    _syncTicker();
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _localRenderer.srcObject = widget.callController.localStream;
    _remoteRenderer.srcObject = widget.callController.remoteStream;
    if (!mounted) {
      return;
    }
    setState(() => _ready = true);
  }

  void _syncTicker() {
    _ticker?.cancel();
    if (widget.callController.state == CallSessionState.connected) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);
    final controller = widget.callController;
    final peer = controller.remotePeer;
    final avatarUrl = AppConfig.resolveMediaUrl(peer?.avatar, settings.baseUrl);
    final status = _statusText(controller, t);

    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready && controller.remoteStream != null)
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: Opacity(
                opacity: 0,
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          if (controller.isVideo &&
              _ready &&
              controller.remoteStream != null)
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1E3344),
                    Color(0xFF0B1620),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CallAvatar(
                      label: peer?.displayName ?? '',
                      imageUrl: avatarUrl,
                      radius: 52,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      peer?.displayName ?? '',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.white70,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peer?.displayName ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (controller.isVideo &&
                      _ready &&
                      controller.localStream != null)
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        width: 112,
                        height: 168,
                        margin: const EdgeInsets.only(top: 16),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RoundActionButton(
                        icon: controller.isMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_none_rounded,
                        backgroundColor: Colors.white24,
                        onPressed: () {
                          unawaited(controller.toggleMute());
                        },
                      ),
                      if (controller.canToggleCamera) ...[
                        const SizedBox(width: 20),
                        _RoundActionButton(
                          icon: controller.isCameraOff
                              ? Icons.videocam_off_rounded
                              : Icons.videocam_rounded,
                          backgroundColor: Colors.white24,
                          onPressed: () {
                            unawaited(controller.toggleCamera());
                          },
                        ),
                      ],
                      const SizedBox(width: 20),
                      _RoundActionButton(
                        icon: Icons.call_end_rounded,
                        backgroundColor: const Color(0xFFE35555),
                        onPressed: () {
                          unawaited(controller.hangUp());
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(
    CallController controller,
    String Function(String key) t,
  ) {
    if (controller.state == CallSessionState.connected &&
        controller.connectedAt != null) {
      final elapsed =
          DateTime.now().difference(controller.connectedAt!).inSeconds;
      return _formatDuration(elapsed);
    }

    switch (controller.state) {
      case CallSessionState.calling:
      case CallSessionState.ringing:
        return t('call_ringing');
      case CallSessionState.connecting:
        return t('call_connecting');
      case CallSessionState.connected:
        return t('call_connected');
      case null:
        return '';
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainder = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.backgroundColor,
    required this.onPressed,
  });

  final IconData icon;
  final Color backgroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _CallAvatar extends StatelessWidget {
  const _CallAvatar({
    required this.label,
    required this.imageUrl,
    required this.radius,
  });

  final String label;
  final String imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(label);
    final hasImage = imageUrl.isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF4A7A9E),
      backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
      child: hasImage
          ? null
          : Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.55,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}
