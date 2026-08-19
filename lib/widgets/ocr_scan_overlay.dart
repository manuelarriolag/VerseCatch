import 'dart:math' as math;

import 'package:flutter/material.dart';

enum OcrOverlayState { scanning, completed, failed }

enum _OcrAmbientEffect { pulseParticles, crossingRays, orbitingNodes }

class OcrScanOverlay extends StatefulWidget {
  const OcrScanOverlay({
    super.key,
    required this.active,
    this.duration = const Duration(seconds: 6),
    this.tint = const Color(0xFFFFA726),
    this.showHud = true,
    this.state = OcrOverlayState.scanning,
    this.errorMessage,
  });

  final bool active;
  final Duration duration;
  final Color tint;
  final bool showHud;
  final OcrOverlayState state;
  final String? errorMessage;

  @override
  State<OcrScanOverlay> createState() => _OcrScanOverlayState();
}

class _OcrScanOverlayState extends State<OcrScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late _OcrAmbientEffect _ambientEffect;

  _OcrAmbientEffect _pickAmbientEffect() {
    final options = _OcrAmbientEffect.values;
    return options[math.Random().nextInt(options.length)];
  }

  @override
  void initState() {
    super.initState();
    _ambientEffect = _pickAmbientEffect();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant OcrScanOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.active && !oldWidget.active) {
      _ambientEffect = _pickAmbientEffect();
    }
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    }
    if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
    if (!widget.active && oldWidget.active && widget.state == OcrOverlayState.scanning) {
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semanticsLabel = switch (widget.state) {
      OcrOverlayState.scanning => 'Procesando imagen mediante OCR',
      OcrOverlayState.completed => 'Texto reconocido',
      OcrOverlayState.failed => 'No fue posible reconocer el texto',
    };

    return IgnorePointer(
      child: Semantics(
        label: semanticsLabel,
        container: true,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final timeline = _timeline(
              progress: _controller.value,
              state: widget.state,
            );
            return Stack(
              key: const ValueKey('ocr-scan-overlay'),
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _OcrScanPainter(
                    progress: _controller.value,
                    tint: widget.tint,
                    state: widget.state,
                    effect: _ambientEffect,
                  ),
                ),
                if (widget.showHud)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: _OcrHud(
                        tint: widget.tint,
                        state: widget.state,
                        status: widget.state == OcrOverlayState.failed
                            ? (widget.errorMessage ?? 'No fue posible reconocer el texto')
                            : timeline.status,
                        progress: timeline.progress,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  ({String status, double progress}) _timeline({
    required double progress,
    required OcrOverlayState state,
  }) {
    if (state == OcrOverlayState.completed) {
      return (status: 'Texto reconocido ✓', progress: 1);
    }
    if (state == OcrOverlayState.failed) {
      return (status: 'No fue posible reconocer el texto', progress: 1);
    }

    const checkpoints = <({double t, double p, String status})>[
      (t: 0.00, p: 0.18, status: 'Preparando imagen...'),
      (t: 0.20, p: 0.32, status: 'Analizando texto...'),
      (t: 0.45, p: 0.47, status: 'Reconociendo citas bíblicas...'),
      (t: 0.68, p: 0.68, status: 'Extrayendo citas bíblicas...'),
      (t: 0.86, p: 0.84, status: 'Extrayendo citas bíblicas...'),
      (t: 1.00, p: 1.00, status: 'Texto reconocido ✓'),
    ];

    for (var i = 0; i < checkpoints.length - 1; i++) {
      final current = checkpoints[i];
      final next = checkpoints[i + 1];
      if (progress <= next.t) {
        final span = (next.t - current.t).clamp(0.0001, 1.0);
        final local = ((progress - current.t) / span).clamp(0.0, 1.0);
        final visualProgress = current.p + ((next.p - current.p) * local);
        return (status: current.status, progress: visualProgress);
      }
    }

    return (status: checkpoints.last.status, progress: checkpoints.last.p);
  }
}

class _OcrHud extends StatelessWidget {
  const _OcrHud({
    required this.tint,
    required this.state,
    required this.status,
    required this.progress,
  });

  final Color tint;
  final OcrOverlayState state;
  final String status;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final barColor = state == OcrOverlayState.failed ? Colors.orange.shade300 : tint;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        key: const ValueKey('ocr-hud-panel'),
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: barColor.withValues(alpha: 0.75)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  state == OcrOverlayState.failed
                      ? Icons.warning_amber_rounded
                      : Icons.circle,
                  size: 10,
                  color: barColor,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Verse Catch',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: progress.clamp(0, 1),
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                color: barColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OcrScanPainter extends CustomPainter {
  _OcrScanPainter({
    required this.progress,
    required this.tint,
    required this.state,
    required this.effect,
  });

  final double progress;
  final Color tint;
  final OcrOverlayState state;
  final _OcrAmbientEffect effect;

  static const double _textBoxWidthFactor = 0.85;

  static const List<Rect> _boxAnchors = <Rect>[
    Rect.fromLTWH(0.16, 0.21, 0.56, 0.055),
    Rect.fromLTWH(0.19, 0.30, 0.48, 0.05),
    Rect.fromLTWH(0.14, 0.39, 0.62, 0.055),
    Rect.fromLTWH(0.22, 0.50, 0.43, 0.05),
    Rect.fromLTWH(0.18, 0.61, 0.52, 0.055),
    Rect.fromLTWH(0.15, 0.71, 0.58, 0.05),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final frameRect = Rect.fromLTWH(
      size.width * 0.06,
      size.height * 0.08,
      size.width * 0.88,
      size.height * 0.84,
    );

    _paintFrameCorners(canvas, frameRect);
    _paintTextBoxes(canvas, frameRect);

    if (state == OcrOverlayState.failed) {
      return;
    }

    final scanY = frameRect.top + frameRect.height * progress;
    _paintScanBeam(canvas, frameRect, scanY);

    switch (effect) {
      case _OcrAmbientEffect.pulseParticles:
        _paintPulseParticles(canvas, frameRect, scanY);
      case _OcrAmbientEffect.crossingRays:
        _paintCrossingRays(canvas, frameRect, scanY);
      case _OcrAmbientEffect.orbitingNodes:
        _paintOrbitingNodes(canvas, frameRect, scanY);
    }
  }

  void _paintFrameCorners(Canvas canvas, Rect frameRect) {
    const cornerLenFactor = 0.12;
    final cornerLen = math.min(frameRect.width, frameRect.height) * cornerLenFactor;
    final cornerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = tint.withValues(alpha: 0.7);

    final cornerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..color = tint.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    Path cornerPath(Offset start, bool horizontalPositive, bool verticalPositive) {
      final h = horizontalPositive ? cornerLen : -cornerLen;
      final v = verticalPositive ? cornerLen : -cornerLen;
      return Path()
        ..moveTo(start.dx + h, start.dy)
        ..lineTo(start.dx, start.dy)
        ..lineTo(start.dx, start.dy + v);
    }

    final corners = <Path>[
      cornerPath(frameRect.topLeft, true, true),
      cornerPath(frameRect.topRight, false, true),
      cornerPath(frameRect.bottomLeft, true, false),
      cornerPath(frameRect.bottomRight, false, false),
    ];

    for (final path in corners) {
      canvas.drawPath(path, cornerGlow);
      canvas.drawPath(path, cornerStroke);
    }
  }

  void _paintScanBeam(Canvas canvas, Rect frameRect, double scanY) {
    final haloRect = Rect.fromLTWH(
      frameRect.left,
      scanY - frameRect.height * 0.055,
      frameRect.width,
      frameRect.height * 0.11,
    );

    final halo = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          tint.withValues(alpha: 0),
          tint.withValues(alpha: 0.05),
          tint.withValues(alpha: 0.16),
          tint.withValues(alpha: 0.05),
          tint.withValues(alpha: 0),
        ],
      ).createShader(haloRect);

    canvas.drawRect(haloRect, halo);

    final beamGlow = Paint()
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = tint.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final beamLine = Paint()
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..color = tint.withValues(alpha: 0.88);

    final start = Offset(frameRect.left + 6, scanY);
    final end = Offset(frameRect.right - 6, scanY);
    canvas.drawLine(start, end, beamGlow);
    canvas.drawLine(start, end, beamLine);
  }

  void _paintTextBoxes(Canvas canvas, Rect frameRect) {
    final textRectStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = tint.withValues(alpha: 0.55);

    final textRectGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = tint.withValues(alpha: 0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final scanY = frameRect.top + frameRect.height * progress;
    final targetWidth = frameRect.width * _textBoxWidthFactor;
    for (final anchor in _boxAnchors) {
      final anchorCenter = frameRect.left +
          frameRect.width * (anchor.left + (anchor.width / 2));
      final left = (anchorCenter - (targetWidth / 2))
          .clamp(frameRect.left, frameRect.right - targetWidth)
          .toDouble();
      final rect = Rect.fromLTWH(
        left,
        frameRect.top + frameRect.height * anchor.top,
        targetWidth,
        frameRect.height * anchor.height,
      );
      final centerY = rect.center.dy;
      final distance = (centerY - scanY).abs() / frameRect.height;
      var visibility = (1 - (distance / 0.16)).clamp(0.0, 1.0);

      final entered = scanY > rect.top - frameRect.height * 0.04;
      if (!entered && state == OcrOverlayState.scanning) {
        visibility = 0;
      }

      if (state == OcrOverlayState.completed) {
        visibility = 0.8;
      }
      if (state == OcrOverlayState.failed) {
        visibility = 0.35;
      }

      if (visibility <= 0.02) continue;

      final glow = textRectGlow..color = tint.withValues(alpha: 0.08 * visibility);
      final stroke = textRectStroke
        ..color = tint.withValues(alpha: (0.3 + (0.55 * visibility)).clamp(0, 0.85));

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rrect, glow);
      canvas.drawRRect(rrect, stroke);
    }
  }

  void _paintPulseParticles(Canvas canvas, Rect frameRect, double scanY) {
    final baseCount = state == OcrOverlayState.completed ? 8 : 12;
    for (var i = 0; i < baseCount; i++) {
      final seed = i + 1;
      final xOffset = ((math.sin((progress * 8) + seed) + 1) / 2) * frameRect.width;
      final wave = math.cos((progress * 11) + (seed * 1.8));
      final particleY = scanY + (wave * 18) + ((seed % 3) - 1) * 6;
      if (particleY < frameRect.top || particleY > frameRect.bottom) continue;

      final center = Offset(frameRect.left + xOffset, particleY);
      final radius = 0.8 + ((seed % 4) * 0.32);
      final opacity = (0.12 + (0.12 * ((math.sin(progress * 12 + seed) + 1) / 2))).clamp(0.08, 0.24);
      final paint = Paint()..color = tint.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintCrossingRays(Canvas canvas, Rect frameRect, double scanY) {
    final phase = progress * (2 * math.pi);
    final lineCount = state == OcrOverlayState.completed ? 4 : 6;
    for (var i = 0; i < lineCount; i++) {
      final t = i / lineCount;
      final y = frameRect.top + (frameRect.height * t);
      final sway = math.sin((phase * 1.3) + (i * 0.9)) * 16;
      final alpha = (0.08 + (0.08 * ((math.cos(phase + i) + 1) / 2))).clamp(
        0.08,
        0.2,
      );

      final paint = Paint()
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..color = tint.withValues(alpha: alpha);

      final start = Offset(frameRect.left + sway, y);
      final end = Offset(frameRect.right - sway, y + (scanY - y) * 0.02);
      canvas.drawLine(start, end, paint);
    }
  }

  void _paintOrbitingNodes(Canvas canvas, Rect frameRect, double scanY) {
    final center = Offset(frameRect.center.dx, scanY);
    final maxRadius = frameRect.width * 0.28;
    final nodeCount = state == OcrOverlayState.completed ? 6 : 9;

    for (var i = 0; i < nodeCount; i++) {
      final phase = (i / nodeCount) * 2 * math.pi;
      final pulse = 0.65 + (0.35 * ((math.sin((progress * 14) + i) + 1) / 2));
      final orbitRadius = maxRadius * (0.32 + ((i % 3) * 0.2));
      final dx = math.cos((progress * 5.4) + phase) * orbitRadius;
      final dy = math.sin((progress * 6.2) + phase) * (frameRect.height * 0.04);
      final node = Offset(center.dx + dx, center.dy + dy);
      if (!frameRect.contains(node)) continue;

      final nodePaint = Paint()
        ..color = tint.withValues(alpha: (0.1 + (0.2 * pulse)).clamp(0.1, 0.3));
      canvas.drawCircle(node, 1.0 + ((i % 4) * 0.35), nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OcrScanPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.tint != tint ||
        oldDelegate.state != state ||
        oldDelegate.effect != effect;
  }
}
