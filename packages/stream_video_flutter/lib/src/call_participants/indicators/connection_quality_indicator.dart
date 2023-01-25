import 'package:flutter/material.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart';

/// Widget used to indicate the connection quality of a given participant.
class StreamConnectionQualityIndicator extends StatelessWidget {
  const StreamConnectionQualityIndicator({
    super.key,
    required this.connectionQuality,
    this.activeColor,
    this.inactiveColor,
  });

  /// The connection quality of the participant.
  final ConnectionQuality connectionQuality;

  /// The color of an active connection quality level.
  final Color? activeColor;

  /// The color of an inactive connection quality level.
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    final theme = StreamVideoTheme.of(context).callParticipantTheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SizedBox(
        width: 24.0,
        height: 24.0,
        child: CustomPaint(
          size: const Size.square(24.0),
          painter: _ConnectionQualityIndicatorPainter(
            connectionQuality: connectionQuality,
            activeColor: activeColor ?? theme.connectionLevelActiveColor,
            inactiveColor: inactiveColor ?? theme.connectionLevelInactiveColor,
          ),
        ),
      ),
    );
  }
}

/// Painter widget for the connection quality indicator widget.
class _ConnectionQualityIndicatorPainter extends CustomPainter {
  /// Constructor for creating a [_ConnectionQualityIndicatorPainter].
  const _ConnectionQualityIndicatorPainter({
    required this.connectionQuality,
    required this.activeColor,
    required this.inactiveColor,
  });

  /// The connection quality of the participant.
  final ConnectionQuality connectionQuality;

  /// The color of an active connection quality level.
  final Color activeColor;

  /// The color of an inactive connection quality level.
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 3; i++) {
      final double offsetLeft = 7 + i * 5;
      final double offsetTop = 14 - i * 3;
      final connectionLevel = _getConnectionLevel();

      canvas.drawLine(
        Offset(offsetLeft, offsetTop),
        Offset(offsetLeft, 16),
        connectionLevel > i ? activePaint : inactivePaint,
      );
    }
  }

  int _getConnectionLevel() {
    switch (connectionQuality) {
      case ConnectionQuality.poor:
        return 1;
      case ConnectionQuality.good:
        return 2;
      case ConnectionQuality.excellent:
        return 3;
      default:
        return 0;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}