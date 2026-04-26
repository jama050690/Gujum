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
  @override State<CallOverlayHost> createState() => _CallOverlayHostState();
}

class _CallOverlayHostState extends State<CallOverlayHost> {
  CallController? _controller;
  int _lastErrorVersion = 0;

  @override void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<CallController?>();
    if (!identical(_controller, next)) {
      _controller?.removeListener(_onChanged);
      _controller = next;
      _controller?.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (!mounted || _controller?.errorKey == null || _controller?.errorVersion == _lastErrorVersion) return;
    _lastErrorVersion = _controller!.errorVersion;
    final msg = AppStrings.text(context.read<SettingsController>().localeCode, _controller!.errorKey!);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override void dispose() { _controller?.removeListener(_onChanged); super.dispose(); }

  @override Widget build(BuildContext context) {
    final controller = context.watch<CallController?>();
    if (controller == null) return widget.child;
    return PopScope(
      canPop: !controller.hasSession && !controller.hasIncomingCall,
      child: Stack(children: [
        widget.child,
        if (controller.hasIncomingCall) Positioned.fill(child: _IncomingCallSheet(callController: controller)),
        if (controller.hasSession) Positioned.fill(child: _ActiveCallSheet(callController: controller)),
      ]),
    );
  }
}

class _IncomingCallSheet extends StatelessWidget {
  const _IncomingCallSheet({required this.callController});
  final CallController callController;
  @override Widget build(BuildContext context) {
    final incoming = callController.incomingCall!;
    final settings = context.watch<SettingsController>();
    final avatar = AppConfig.resolveMediaUrl(incoming.caller.avatar, settings.baseUrl);
    return ColoredBox(
      color: Colors.black.withAlpha(200),
      child: Center(child: Container(
        width: 320, padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: settings.isDarkMode ? const Color(0xFF1C2733) : Colors.white, borderRadius: BorderRadius.circular(32)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 48, backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null),
          const SizedBox(height: 20),
          Text(incoming.caller.displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _RoundActionButton(icon: Icons.call_end, backgroundColor: Colors.red, onPressed: () => callController.rejectIncomingCall()),
            _RoundActionButton(icon: incoming.isVideo ? Icons.videocam : Icons.call, backgroundColor: Colors.green, onPressed: () => unawaited(callController.acceptIncomingCall())),
          ]),
        ]),
      )),
    );
  }
}

class _ActiveCallSheet extends StatefulWidget {
  const _ActiveCallSheet({required this.callController});
  final CallController callController;
  @override State<_ActiveCallSheet> createState() => _ActiveCallSheetState();
}

class _ActiveCallSheetState extends State<_ActiveCallSheet> {
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  bool _ready = false;

  @override void initState() { super.initState(); _init(); widget.callController.addListener(_update); }
  @override void dispose() { widget.callController.removeListener(_update); _local.dispose(); _remote.dispose(); super.dispose(); }

  Future<void> _init() async {
    await _local.initialize(); await _remote.initialize();
    if (mounted) setState(() => _ready = true); _sync();
  }

  void _update() { _sync(); if (mounted) setState(() {}); }
  void _sync() {
    if (!_ready) return;
    _local.srcObject = widget.callController.localStream;
    _remote.srcObject = widget.callController.remoteStream;
  }

  @override Widget build(BuildContext context) {
    final ctrl = widget.callController;
    final peer = ctrl.remotePeer;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (ctrl.isVideo && ctrl.remoteStream != null && _ready)
          RTCVideoView(_remote, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
        else
          Center(child: Text(peer?.displayName ?? '', style: const TextStyle(color: Colors.white, fontSize: 24))),
        
        if (ctrl.isVideo && !ctrl.isCameraOff && _ready)
          Positioned(top: 50, right: 20, width: 120, height: 180, child: RTCVideoView(_local, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
        
        Positioned(bottom: 40, left: 0, right: 0, 
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, 
            children: [
              // 1. MIKROFON (Har doim bor)
              _RoundActionButton(
                icon: ctrl.isMuted ? Icons.mic_off : Icons.mic, 
                backgroundColor: ctrl.isMuted ? Colors.white : Colors.white12, 
                iconColor: ctrl.isMuted ? Colors.black : Colors.white,
                onPressed: () => ctrl.toggleMute()
              ),
              const SizedBox(width: 16),
              
              // --- DINAMIK TUGMALAR ---
              if (ctrl.isVideo) ...[
                // Video rejimda: Audioga o'tish tugmasi
                _RoundActionButton(
                  icon: Icons.phone_enabled, 
                  backgroundColor: Colors.white12, 
                  onPressed: () => ctrl.switchCallMode(false)
                ),
                const SizedBox(width: 16),
                // Video rejimda: Kamerani yopish tugmasi
                _RoundActionButton(
                  icon: ctrl.isCameraOff ? Icons.videocam_off : Icons.videocam, 
                  backgroundColor: ctrl.isCameraOff ? Colors.white : Colors.white12, 
                  iconColor: ctrl.isCameraOff ? Colors.black : Colors.white,
                  onPressed: () => ctrl.toggleCamera()
                ),
              ] else ...[
                // Audio rejimda: Faqat videoga o'tish tugmasi (jami 3 ta tugma bo'lishi uchun)
                _RoundActionButton(
                  icon: Icons.videocam, 
                  backgroundColor: Colors.white12, 
                  onPressed: () => ctrl.switchCallMode(true)
                ),
              ],
              
              const SizedBox(width: 16),
              
              // 4. YAKUNLASH (Har doim bor)
              _RoundActionButton(
                icon: Icons.call_end, 
                backgroundColor: Colors.red, 
                onPressed: () => ctrl.hangUp()
              ),
            ]
          )
        ),
      ]),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({required this.icon, required this.backgroundColor, required this.onPressed, this.iconColor = Colors.white});
  final IconData icon; final Color backgroundColor; final Color iconColor; final VoidCallback onPressed;
  @override Widget build(BuildContext context) {
    return Container(
      width: 60, height: 60, 
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: iconColor, size: 28), 
        onPressed: onPressed
      ),
    );
  }
}
