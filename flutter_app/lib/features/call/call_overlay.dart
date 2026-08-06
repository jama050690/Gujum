import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _CallOverlayHostState extends State<CallOverlayHost>
    with WidgetsBindingObserver {
  CallController? _controller;
  int _lastErrorVersion = 0;
  OverlayEntry? _callOverlayEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateOverlay();
    }
  }

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
    if (!mounted) return;
    if (_controller?.errorKey != null &&
        _controller?.errorVersion != _lastErrorVersion) {
      _lastErrorVersion = _controller!.errorVersion;
      final msg = AppStrings.text(
          context.read<SettingsController>().localeCode, _controller!.errorKey!);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    _updateOverlay();
  }

  void _updateOverlay() {
    if (!mounted) return;
    final ctrl = _controller;
    final shouldShow = ctrl != null && (ctrl.hasIncomingCall || ctrl.hasSession);
    if (shouldShow && _callOverlayEntry == null) {
      _showCallOverlay();
    } else if (!shouldShow && _callOverlayEntry != null) {
      _removeCallOverlay();
    } else if (_callOverlayEntry != null) {
      _callOverlayEntry!.markNeedsBuild();
    }
  }

  void _showCallOverlay() {
    final ctrl = _controller;
    if (ctrl == null || !mounted) return;
    _dismissKeyboard();
    _callOverlayEntry = OverlayEntry(
      builder: (ctx) {
        if (ctrl.hasIncomingCall) {
          return _IncomingCallSheet(callController: ctrl);
        }
        if (ctrl.hasSession) {
          return _ActiveCallSheet(callController: ctrl);
        }
        return const SizedBox.shrink();
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_callOverlayEntry!);
  }

  void _removeCallOverlay() {
    _callOverlayEntry?.remove();
    _callOverlayEntry = null;
    // Ochiq bottom sheet yoki dialog qolgan bo'lsa yopamiz
    if (mounted) {
      try {
        final nav = Navigator.of(context, rootNavigator: false);
        nav.popUntil((route) => route is! PopupRoute);
      } catch (_) {}
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onChanged);
    _removeCallOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CallController?>();
    return PopScope(
      canPop: controller == null ||
          (!controller.hasSession && !controller.hasIncomingCall),
      child: widget.child,
    );
  }
}

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2).toList();
  if (parts.isEmpty) return '?';
  return parts.map((s) => s.substring(0, 1).toUpperCase()).join();
}

class _IncomingCallSheet extends StatefulWidget {
  const _IncomingCallSheet({required this.callController});
  final CallController callController;
  @override
  State<_IncomingCallSheet> createState() => _IncomingCallSheetState();
}

class _IncomingCallSheetState extends State<_IncomingCallSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = widget.callController.incomingCall!;
    final settings = context.watch<SettingsController>();
    final avatar = AppConfig.resolveMediaUrl(incoming.caller.avatar, settings.baseUrl);
    final initials = _initials(incoming.caller.displayName);
    final typeLabel = incoming.isVideo ? "Video qo'ng'iroq" : "Ovozli qo'ng'iroq";

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF182644), Color(0xFF0D1B2E), Color(0xFF060D18)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 52),
              Text(
                typeLabel,
                style: const TextStyle(
                  color: Color(0xFF7EB6FF),
                  fontSize: 17,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              _PulsingAvatar(animation: _pulse, avatarUrl: avatar, initials: initials),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  incoming.caller.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallActionButton(
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFE53935),
                    label: 'Rad etish',
                    onPressed: () => widget.callController.rejectIncomingCall(),
                  ),
                  _CallActionButton(
                    icon: incoming.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    color: const Color(0xFF43A047),
                    label: 'Qabul qilish',
                    onPressed: () => unawaited(widget.callController.acceptIncomingCall()),
                  ),
                ],
              ),
              const SizedBox(height: 56),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingAvatar extends StatelessWidget {
  const _PulsingAvatar({
    required this.animation,
    required this.avatarUrl,
    required this.initials,
  });
  final Animation<double> animation;
  final String avatarUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(animation.value);
        return SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.25,
                child: Container(
                  width: 200 + t * 18,
                  height: 200 + t * 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF4A90E2), width: 1.5),
                  ),
                ),
              ),
              Opacity(
                opacity: (1 - t) * 0.45,
                child: Container(
                  width: 168 + t * 14,
                  height: 168 + t * 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF4A90E2), width: 2),
                  ),
                ),
              ),
              CircleAvatar(
                radius: 72,
                backgroundColor: const Color(0xFF2D5FCC).withAlpha(120),
                backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 52,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 14)),
      ],
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
  Timer? _ticker;
  bool _audioInitialized = false;
  bool _lastIsVideo = false;
  int _lastRemoteStreamVersion = 0;
  int _lastLocalStreamVersion = 0;

  // Self-view is free-positioned: dragged anywhere, clamped so it can never be
  // left partly off-screen. null = the default bottom-right resting spot.
  static const double _pipWidth = 132;
  static const double _pipHeight = 188;
  Offset? _pipOffset;

  // Controls auto-hide only during a connected video call — on an audio call
  // there is nothing underneath worth uncovering, so they stay put.
  bool _controlsVisible = true;
  bool _autoHideArmed = false;
  Timer? _controlsHideTimer;
  static const _controlsHideDelay = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _init();
    widget.callController.addListener(_update);
  }

  @override
  void dispose() {
    widget.callController.removeListener(_update);
    _ticker?.cancel();
    _controlsHideTimer?.cancel();
    _local.dispose();
    _remote.dispose();
    super.dispose();
  }

  bool _shouldAutoHideControls(CallController ctrl) =>
      ctrl.isVideo && ctrl.state == CallSessionState.connected;

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(_controlsHideDelay, () {
      if (!mounted) return;
      if (!_shouldAutoHideControls(widget.callController)) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    // Outside an active video call the dock is always on, so a tap is a no-op
    // rather than a way to strand the user with no way to hang up.
    if (!_shouldAutoHideControls(widget.callController)) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleControlsHide();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  // Armed once per transition into an active video call — not on every notify,
  // or the 1 s timer would keep pushing the hide back forever.
  void _syncControlsAutoHide() {
    final autoHide = _shouldAutoHideControls(widget.callController);
    if (autoHide && !_autoHideArmed) {
      _autoHideArmed = true;
      _scheduleControlsHide();
    } else if (!autoHide && _autoHideArmed) {
      _autoHideArmed = false;
      _controlsHideTimer?.cancel();
      _controlsHideTimer = null;
      _controlsVisible = true;
    }
  }

  Offset _defaultPipOffset(Size screen) => Offset(
        screen.width - _pipWidth - 22,
        screen.height - _pipHeight - 188,
      );

  Offset _clampPip(Offset value, Size screen) {
    const margin = 12.0;
    final maxX = screen.width - _pipWidth - margin;
    final maxY = screen.height - _pipHeight - margin;
    return Offset(
      maxX <= margin ? margin : value.dx.clamp(margin, maxX),
      maxY <= margin ? margin : value.dy.clamp(margin, maxY),
    );
  }

  Future<void> _init() async {
    await _local.initialize();
    await _remote.initialize();
    if (mounted) setState(() => _ready = true);
    _sync();
    _syncTicker();
  }

  void _update() {
    _sync();
    _syncTicker();
    _syncControlsAutoHide();
    if (mounted) setState(() {});
  }

  void _sync() {
    if (!_ready) return;
    final localVersion = widget.callController.localStreamVersion;
    final localVersionChanged = localVersion != _lastLocalStreamVersion;
    if (localVersionChanged) {
      _lastLocalStreamVersion = localVersion;
      _local.srcObject = null;
      _local.srcObject = widget.callController.localStream;
    } else {
      _local.srcObject = widget.callController.localStream;
    }
    final remote = widget.callController.remoteStream;
    final isConnected =
        widget.callController.state == CallSessionState.connected;
    final isVideo = widget.callController.isVideo;
    final videoJustEnabled = isVideo && !_lastIsVideo;
    _lastIsVideo = isVideo;

    final streamVersion = widget.callController.remoteStreamVersion;
    final versionChanged = streamVersion != _lastRemoteStreamVersion;
    if (versionChanged) {
      _lastRemoteStreamVersion = streamVersion;
      _audioInitialized = false;
    }

    if (_remote.srcObject?.id != remote?.id || videoJustEnabled || versionChanged) {
      _remote.srcObject = null;
      _remote.srcObject = remote;
      _audioInitialized = false;
    }
    if (!_audioInitialized && isConnected && remote != null) {
      _remote.srcObject = null;
      _remote.srcObject = remote;
      _audioInitialized = true;
    }
  }

  void _syncTicker() {
    final connectedAt = widget.callController.connectedAt;
    if (connectedAt == null) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.callController;
    final peer = ctrl.remotePeer;
    final settings = context.watch<SettingsController>();
    final avatarUrl = AppConfig.resolveMediaUrl(peer?.avatar, settings.baseUrl);
    final showRemoteVideo = ctrl.isVideo && ctrl.hasRemoteVideo && _ready;
    final statusText = _buildStatusText(context, ctrl);
    final timerText = _buildTimerText(ctrl.connectedAt);
    final titleText = peer?.displayName ?? peer?.username ?? '';
    final subtitleText = timerText ?? statusText;
    final screen = MediaQuery.sizeOf(context);
    final pipPos = _clampPip(_pipOffset ?? _defaultPipOffset(screen), screen);

    return Scaffold(
      backgroundColor: const Color(0xFF09111C),
      body: GestureDetector(
        // Taps that land on a button hit it first; this only catches the
        // background, which is what toggles the dock during a video call.
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0C111A),
                  Color(0xFF0A0F17),
                  Color(0xFF04070C),
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
                  center: Alignment(0, -0.04),
                  radius: 0.92,
                  colors: [
                    Color(0xFF13233B),
                    Color(0xFF0C1625),
                    Color(0xFF060A10),
                  ],
                ),
              ),
              child: _buildAudioLayout(
                titleText: titleText,
                subtitleText: subtitleText,
                avatarUrl: avatarUrl,
                ctrl: ctrl,
              ),
            ),
          ),
        if (showRemoteVideo)
          Positioned(
            top: 64,
            left: 28,
            right: 28,
            child: SafeArea(
              bottom: false,
              child: Column(children: [
                Text(
                  titleText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitleText,
                  style: const TextStyle(
                    color: Color(0xD9FFFFFF),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          ),
        if (ctrl.isVideo && !ctrl.isCameraOff && _ready)
          Positioned(
            left: pipPos.dx,
            top: pipPos.dy,
            width: _pipWidth,
            height: _pipHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => setState(() {
                _pipOffset = _clampPip(pipPos + details.delta, screen);
              }),
              child: _LocalPreviewCard(renderer: _local, ctrl: ctrl),
            ),
          ),
        Positioned(
          bottom: 36,
          left: 20,
          right: 20,
          child: SafeArea(
            top: false,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _ControlsDock(ctrl: ctrl),
              ),
            ),
          ),
        ),
        ]),
      ),
    );
  }

  Widget _buildAudioLayout({
    required String titleText,
    required String subtitleText,
    required String avatarUrl,
    required CallController ctrl,
  }) {
    final initials = _initials(titleText);
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 74),
          Text(
            titleText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            subtitleText,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          _AvatarGlow(
            avatarUrl: avatarUrl,
            initials: initials,
            isVideo: ctrl.isVideo,
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  String _buildStatusText(BuildContext context, CallController ctrl) {
    final localeCode = context.read<SettingsController>().localeCode;
    switch (ctrl.state) {
      case CallSessionState.connected:
        return AppStrings.text(localeCode, 'call_connected');
      case CallSessionState.calling:
        return AppStrings.text(localeCode, 'call_ringing');
      case CallSessionState.connecting:
        return AppStrings.text(localeCode, 'call_connecting');
      case CallSessionState.ringing:
        return AppStrings.text(localeCode, 'call_incoming');
      case null:
        return '';
    }
  }

  String? _buildTimerText(DateTime? connectedAt) {
    if (connectedAt == null) {
      return null;
    }
    final duration = DateTime.now().difference(connectedAt);
    if (duration.isNegative) return '00:00';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
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
      this.enabled = true,
      this.iconColor = Colors.white,
      this.size = 52,
      this.iconSize = 26});
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onPressed;
  final bool enabled;
  final double size;
  final double iconSize;
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        width: size,
        height: size,
        decoration:
            BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
        child: IconButton(
          icon: Icon(icon, color: iconColor, size: iconSize),
          onPressed: enabled ? onPressed : null,
        ),
      ),
    );
  }
}

class _AvatarGlow extends StatelessWidget {
  const _AvatarGlow({
    required this.avatarUrl,
    required this.initials,
    required this.isVideo,
  });

  final String avatarUrl;
  final String initials;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      height: 360,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D6FFF).withAlpha(58),
                  blurRadius: 64,
                  spreadRadius: 24,
                ),
                BoxShadow(
                  color: const Color(0xFF724BFF).withAlpha(46),
                  blurRadius: 92,
                  spreadRadius: 12,
                ),
              ],
            ),
          ),
          Container(
            width: isVideo ? 220 : 210,
            height: isVideo ? 220 : 210,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFC654),
                  Color(0xFFFFA52F),
                ],
              ),
            ),
            child: CircleAvatar(
              backgroundColor: Colors.transparent,
              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty
                  ? Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalPreviewCard extends StatelessWidget {
  const _LocalPreviewCard({required this.renderer, required this.ctrl});

  final RTCVideoRenderer renderer;
  final CallController ctrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F29),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(70),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RTCVideoView(
              renderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            Positioned(
              top: 10,
              right: 10,
              child: GestureDetector(
                onTap: () => ctrl.flipCamera(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(130),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ctrl.isFrontCamera
                        ? Icons.flip_camera_ios
                        : Icons.flip_camera_android,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(110),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'You',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsDock extends StatelessWidget {
  const _ControlsDock({required this.ctrl});

  final CallController ctrl;

  @override
  Widget build(BuildContext context) {
    final canToggleCamera = ctrl.canToggleCamera;
    final List<Widget> actions = <Widget>[
      _SpeakerButton(ctrl: ctrl),
      _RoundActionButton(
        icon: ctrl.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
        backgroundColor: Colors.transparent,
        size: 52,
        onPressed: () => ctrl.toggleMute(),
      ),
      _RoundActionButton(
        icon: ctrl.isVideo
            ? (ctrl.isCameraOff
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded)
            : Icons.videocam_outlined,
        backgroundColor: ctrl.isVideo && ctrl.isCameraOff
            ? Colors.white
            : Colors.transparent,
        iconColor:
            ctrl.isVideo && ctrl.isCameraOff ? Colors.black : Colors.white,
        enabled: canToggleCamera,
        size: 62,
        iconSize: 28,
        onPressed: () => ctrl.toggleCamera(),
      ),
      _RoundActionButton(
        icon: Icons.call_end_rounded,
        backgroundColor: const Color(0xFFD84D68),
        size: 62,
        iconSize: 28,
        onPressed: () => ctrl.hangUp(),
      ),
    ];

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF14161C).withAlpha(244),
          borderRadius: BorderRadius.circular(34),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(70),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: actions,
        ),
      ),
    );
  }

}

class _SpeakerButton extends StatefulWidget {
  const _SpeakerButton({required this.ctrl});
  final CallController ctrl;

  @override
  State<_SpeakerButton> createState() => _SpeakerButtonState();
}

class _SpeakerButtonState extends State<_SpeakerButton> {
  int _tapCount = 0;
  Timer? _tapTimer;
  OverlayEntry? _optionsEntry;
  final _btnKey = GlobalKey();
  static const _doubleTapWindow = Duration(milliseconds: 300);

  @override
  void dispose() {
    _tapTimer?.cancel();
    _dismissOptions();
    super.dispose();
  }

  void _onTap() {
    if (_optionsEntry != null) {
      _dismissOptions();
      return;
    }
    _tapCount++;
    if (_tapCount == 1) {
      _tapTimer = Timer(_doubleTapWindow, () {
        if (mounted) {
          _cycleRoute();
          _tapCount = 0;
        }
      });
    } else {
      _tapTimer?.cancel();
      _tapCount = 0;
      _showOptions();
    }
  }

  void _cycleRoute() {
    final ctrl = widget.ctrl;
    switch (ctrl.audioRoute) {
      case CallAudioRoute.earpiece:
        ctrl.setAudioRoute(CallAudioRoute.speaker);
      case CallAudioRoute.speaker:
        ctrl.setAudioRoute(
          ctrl.hasBluetoothAudio ? CallAudioRoute.bluetooth : CallAudioRoute.earpiece,
        );
      case CallAudioRoute.bluetooth:
      case CallAudioRoute.headset:
        ctrl.setAudioRoute(CallAudioRoute.earpiece);
    }
  }

  void _showOptions() {
    final box = _btnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.sizeOf(_btnKey.currentContext!).height;
    final ctrl = widget.ctrl;

    _optionsEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // Dismiss barrier — tashqarini bosib yopish
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissOptions,
              behavior: HitTestBehavior.opaque,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          // Popup: button tepasida joylashadi
          Positioned(
            left: (pos.dx - 56).clamp(8.0, double.infinity),
            bottom: screenH - pos.dy + 12,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2230),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(80),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AudioRouteOption(
                      icon: Icons.phone_in_talk_rounded,
                      selected: ctrl.audioRoute == CallAudioRoute.earpiece,
                      onTap: () {
                        _dismissOptions();
                        ctrl.setAudioRoute(CallAudioRoute.earpiece);
                      },
                    ),
                    const SizedBox(width: 8),
                    _AudioRouteOption(
                      icon: Icons.volume_up_rounded,
                      selected: ctrl.audioRoute == CallAudioRoute.speaker,
                      onTap: () {
                        _dismissOptions();
                        ctrl.setAudioRoute(CallAudioRoute.speaker);
                      },
                    ),
                    if (ctrl.hasBluetoothAudio) ...[
                      const SizedBox(width: 8),
                      _AudioRouteOption(
                        icon: Icons.bluetooth_audio_rounded,
                        selected: ctrl.audioRoute == CallAudioRoute.bluetooth,
                        onTap: () {
                          _dismissOptions();
                          ctrl.setAudioRoute(CallAudioRoute.bluetooth);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(_btnKey.currentContext!, rootOverlay: true).insert(_optionsEntry!);
  }

  void _dismissOptions() {
    _optionsEntry?.remove();
    _optionsEntry = null;
  }

  IconData _iconFor(CallController ctrl) {
    if (ctrl.audioRoute == CallAudioRoute.bluetooth) return Icons.bluetooth_audio_rounded;
    if (ctrl.audioRoute == CallAudioRoute.headset) return Icons.headset_rounded;
    return ctrl.isSpeakerOn ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        key: _btnKey,
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: ctrl.audioRoute == CallAudioRoute.bluetooth
              ? Colors.blue.withAlpha(80)
              : ctrl.audioRoute == CallAudioRoute.headset
                  ? Colors.green.withAlpha(80)
                  : ctrl.isSpeakerOn
                      ? Colors.white.withAlpha(50)
                      : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(_iconFor(ctrl), color: Colors.white, size: 28),
      ),
    );
  }
}

class _AudioRouteOption extends StatelessWidget {
  const _AudioRouteOption({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent.withAlpha(60) : Colors.white12,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: Colors.blueAccent, width: 2) : null,
        ),
        child: Icon(
          icon,
          color: selected ? Colors.blueAccent : Colors.white70,
          size: 28,
        ),
      ),
    );
  }
}
