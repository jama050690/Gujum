part of '../chat_page.dart';

class _InlineAudioMessage extends StatefulWidget {
  const _InlineAudioMessage({
    required this.audioUrl,
    required this.isMine,
    required this.label,
  });

  final String audioUrl;
  final bool isMine;
  final String label;

  @override
  State<_InlineAudioMessage> createState() => _InlineAudioMessageState();
}

class _InlineAudioMessageState extends State<_InlineAudioMessage> {
  late final AudioPlayer _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _muted = false;
  bool _hasSource = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.setReleaseMode(ReleaseMode.stop);
    _durationSub = _player.onDurationChanged.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() => _duration = value);
    });
    _preloadDuration();
    _positionSub = _player.onPositionChanged.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() => _position = value);
    });
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() => _playing = state == PlayerState.playing);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = Duration.zero;
        _playing = false;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _InlineAudioMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _resetSource();
    }
  }

  Future<void> _preloadDuration() async {
    try {
      await _player.setSource(UrlSource(widget.audioUrl));
      final d = await _player.getDuration();
      if (!mounted) return;
      setState(() {
        if (d != null) _duration = d;
        _hasSource = true;
      });
    } catch (_) {}
  }

  Future<void> _resetSource() async {
    _hasSource = false;
    _error = false;
    _duration = Duration.zero;
    _position = Duration.zero;
    await _player.stop();
    if (mounted) {
      setState(() {});
    }
    _preloadDuration();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    try {
      if (!_hasSource) {
        await _player.play(UrlSource(widget.audioUrl));
        _hasSource = true;
      } else {
        await _player.resume();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = true);
      }
    }
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _player.setVolume(next ? 0.0 : 1.0);
    if (mounted) {
      setState(() => _muted = next);
    }
  }

  Future<void> _seek(double value) async {
    await _player.seek(Duration(milliseconds: value.round()));
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return _InlineAudioFallback(
        label: widget.label,
        onTap: _togglePlay,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = widget.isMine
        ? (isDark ? const Color(0xFF24364A) : Colors.white.withAlpha(230))
        : (isDark ? const Color(0xFF223243) : Colors.black.withAlpha(12));
    final textColor = isDark ? Colors.white70 : Colors.black54;
    const active = Color(0xFF3A8BCD);
    final inactive = isDark ? Colors.white24 : Colors.black26;

    final maxMs = _duration.inMilliseconds.toDouble();
    final currentMs = _position.inMilliseconds.toDouble();
    final sliderMax = maxMs > 0 ? maxMs : 1.0;
    final sliderValue =
        maxMs > 0 ? currentMs.clamp(0.0, maxMs).toDouble() : 0.0;
    final timeLabel =
        '${_formatAudioDuration(_position)} / ${_formatAudioDuration(_duration)}';

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 26 : 12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            InkResponse(
              onTap: _togglePlay,
              radius: 20,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: active.withAlpha(38),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: active,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              timeLabel,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: textColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 10),
                  activeTrackColor: active,
                  inactiveTrackColor: inactive,
                  thumbColor: active,
                ),
                child: Slider(
                  value: sliderValue,
                  max: sliderMax,
                  onChanged: maxMs > 0 ? _seek : null,
                ),
              ),
            ),
            IconButton(
              onPressed: _toggleMute,
              icon: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 18,
                color: textColor,
              ),
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            Icon(
              Icons.more_vert_rounded,
              size: 16,
              color: textColor.withAlpha(180),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineAudioFallback extends StatelessWidget {
  const _InlineAudioFallback({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_none_rounded, size: 18),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
