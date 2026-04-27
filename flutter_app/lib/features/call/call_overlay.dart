import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';
import 'call_controller.dart';

class CallOverlayHost extends StatefulWidget {
  const CallOverlayHost({super.key, required this.child});
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
    final next = context.read<CallController?>();
    if (!identical(_controller, next)) {
      _controller?.removeListener(_onChanged);
      _controller = next;
      _controller?.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (!mounted ||
        _controller?.errorKey == null ||
        _controller?.errorVersion == _lastErrorVersion) {
      return;
    }
    _lastErrorVersion = _controller!.errorVersion;
    final msg = AppStrings.text(
        context.read<SettingsController>().localeCode, _controller!.errorKey!);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CallController?>();
    if (controller == null) return widget.child;
    return PopScope(
      canPop: !controller.hasSession && !controller.hasIncomingCall,
      child: Stack(children: [
        widget.child,
        if (controller.hasIncomingCall)
          Positioned.fill(
              child: _IncomingCallSheet(callController: controller)),
        if (controller.hasSession)
          Positioned.fill(child: _ActiveCallSheet(callController: controller)),
      ]),
    );
  }
}

class _IncomingCallSheet extends StatelessWidget {
  const _IncomingCallSheet({required this.callController});
  final CallController callController;
  @override
  Widget build(BuildContext context) {
    final incoming = callController.incomingCall!;
    final settings = context.watch<SettingsController>();
    final avatar =
        AppConfig.resolveMediaUrl(incoming.caller.avatar, settings.baseUrl);
    return ColoredBox(
      color: Colors.black.withAlpha(200),
      child: Center(
          child: Container(
        width: 320,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: settings.isDarkMode ? const Color(0xFF1C2733) : Colors.white,
            borderRadius: BorderRadius.circular(32)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
              radius: 48,
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null),
          const SizedBox(height: 20),
          Text(incoming.caller.displayName,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _RoundActionButton(
                icon: Icons.call_end,
                backgroundColor: Colors.red,
                onPressed: () => callController.rejectIncomingCall()),
            _RoundActionButton(
                icon: incoming.isVideo ? Icons.videocam : Icons.call,
                backgroundColor: Colors.green,
                onPressed: () =>
                    unawaited(callController.acceptIncomingCall())),
          ]),
        ]),
      )),
    );
  }
}

class _ActiveCallSheet extends StatefulWidget {
  const _ActiveCallSheet({required this.callController});
  final CallController callController;
  @override
  State<_ActiveCallSheet> createState() => _ActiveCallSheetState();
}

class _ActiveCallSheetState extends State<_ActiveCallSheet> {
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
    widget.callController.addListener(_update);
  }

  @override
  void dispose() {
    widget.callController.removeListener(_update);
    _local.dispose();
    _remote.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _local.initialize();
    await _remote.initialize();
    if (mounted) setState(() => _ready = true);
    _sync();
  }

  void _update() {
    _sync();
    if (mounted) setState(() {});
  }

  void _sync() {
    if (!_ready) return;
    _local.srcObject = widget.callController.localStream;
    _remote.srcObject = widget.callController.remoteStream;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.callController;
    final peer = ctrl.remotePeer;
    final settings = context.watch<SettingsController>();
    final avatarUrl = AppConfig.resolveMediaUrl(peer?.avatar, settings.baseUrl);
    final showRemoteVideo = ctrl.isVideo && ctrl.remoteStream != null && _ready;
    final statusText = _buildStatusText(context, ctrl);
    final timerText = _buildTimerText(ctrl.connectedAt);

    return Scaffold(
      backgroundColor: const Color(0xFF09111C),
      body: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1C2738),
                  Color(0xFF101A28),
                  Color(0xFF05080E),
                ],
              ),
            ),
          ),
        ),
        if (showRemoteVideo)
          RTCVideoView(_remote,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
        else
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, 0.1),
                  radius: 0.85,
                  colors: [
                    Color(0xFF1C2A40),
                    Color(0xFF0F1724),
                    Color(0xFF05080E),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 52),
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: Color(0xFF4AA3FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.5,
                      ),
                    ),
                    if (timerText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        timerText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Container(
                      width: 188,
                      height: 188,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2B7BFF).withAlpha(40),
                            blurRadius: 36,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 94,
                        backgroundColor: const Color(0xFF223046),
                        backgroundImage: avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl.isEmpty
                            ? Text(
                                _initialsFor(
                                    peer?.displayName ?? peer?.username ?? '?'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 54,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      peer?.displayName ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if ((peer?.username ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '@${peer!.username}',
                        style: const TextStyle(
                          color: Color(0xFF8D99A8),
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (ctrl.state != CallSessionState.connected) ...[
                      const SizedBox(height: 26),
                      const _ConnectingDots(),
                    ],
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ),
        if (showRemoteVideo)
          Positioned(
            top: 52,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Text(
                    statusText,
                    style: const TextStyle(
                      color: Color(0xFF7EB8FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3.5,
                    ),
                  ),
                  if (timerText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      timerText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (ctrl.isVideo && !ctrl.isCameraOff && _ready)
          Positioned(
              top: 50,
              right: 20,
              width: 120,
              height: 180,
              child: RTCVideoView(_local,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
        Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: SafeArea(
                top: false,
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  // 1. MIKROFON (Har doim bor)
                  _RoundActionButton(
                      icon: ctrl.isMuted ? Icons.mic_off : Icons.mic,
                      backgroundColor:
                          ctrl.isMuted ? Colors.white : Colors.white12,
                      iconColor: ctrl.isMuted ? Colors.black : Colors.white,
                      onPressed: () => ctrl.toggleMute()),
                  const SizedBox(width: 16),

                  // --- DINAMIK TUGMALAR ---
                  if (ctrl.isVideo) ...[
                    _RoundActionButton(
                      icon: ctrl.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                      backgroundColor: Colors.white12,
                      onPressed: () => ctrl.toggleSpeaker(),
                    ),
                    const SizedBox(width: 16),
                    _RoundActionButton(
                        icon: ctrl.isCameraOff
                            ? Icons.videocam_off
                            : Icons.videocam,
                        backgroundColor:
                            ctrl.isCameraOff ? Colors.white : Colors.white12,
                        iconColor:
                            ctrl.isCameraOff ? Colors.black : Colors.white,
                        onPressed: () => ctrl.toggleCamera()),
                  ] else ...[
                    _RoundActionButton(
                      icon: ctrl.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                      backgroundColor:
                          ctrl.isSpeakerOn ? Colors.white : Colors.white12,
                      iconColor: ctrl.isSpeakerOn ? Colors.black : Colors.white,
                      onPressed: () => ctrl.toggleSpeaker(),
                    ),
                  ],

                  const SizedBox(width: 16),

                  // 4. YAKUNLASH (Har doim bor)
                  _RoundActionButton(
                      icon: Icons.call_end,
                      backgroundColor: Colors.red,
                      onPressed: () => ctrl.hangUp()),
                ]))),
      ]),
    );
  }

  String _buildStatusText(BuildContext context, CallController ctrl) {
    switch (ctrl.state) {
      case CallSessionState.connected:
        return 'ALOQADA';
      case CallSessionState.calling:
      case CallSessionState.connecting:
        return 'ULANMOQDA...';
      case CallSessionState.ringing:
        return 'QO\'NG\'IROQ KELYAPTI';
      case null:
        return '';
    }
  }

  String? _buildTimerText(DateTime? connectedAt) {
    if (connectedAt == null) {
      return null;
    }
    final duration = DateTime.now().difference(connectedAt);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _initialsFor(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .take(2)
        .toList(growable: false);
    if (parts.isEmpty) {
      return '?';
    }
    return parts.map((item) => item.substring(0, 1).toUpperCase()).join();
  }
}

class _ConnectingDots extends StatefulWidget {
  const _ConnectingDots();

  @override
  State<_ConnectingDots> createState() => _ConnectingDotsState();
}

class _ConnectingDotsState extends State<_ConnectingDots> {
  int _activeIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _activeIndex = (_activeIndex + 1) % 3;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(3, (index) {
        final active = index == _activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2E8CFF) : const Color(0xFF436385),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton(
      {required this.icon,
      required this.backgroundColor,
      required this.onPressed,
      this.iconColor = Colors.white});
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: IconButton(
          icon: Icon(icon, color: iconColor, size: 28), onPressed: onPressed),
    );
  }
}
