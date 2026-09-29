import 'package:flutter/material.dart';

import '../models/capture_evidence.dart';
import '../app.dart';

class OcrImageReview extends StatelessWidget {
  const OcrImageReview({super.key, required this.evidence});

  final CaptureEvidence evidence;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          foregroundPainter: _OcrBoxPainter(evidence: evidence),
          child: ColoredBox(
            color: AppColors.ink,
            child: Image.memory(evidence.imageBytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _OcrBoxPainter extends CustomPainter {
  _OcrBoxPainter({required this.evidence});

  final CaptureEvidence evidence;

  @override
  void paint(Canvas canvas, Size size) {
    if (evidence.imageWidth <= 0 || evidence.imageHeight <= 0) return;
    final sourceSize = Size(
      evidence.imageWidth.toDouble(),
      evidence.imageHeight.toDouble(),
    );
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final scaleX = destination.width / sourceSize.width;
    final scaleY = destination.height / sourceSize.height;
    final paint = Paint()
      ..color = const Color(0xFFB9E4A8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final block in evidence.blocks) {
      final rect = Rect.fromLTRB(
        destination.left + block.left * scaleX,
        destination.top + block.top * scaleY,
        destination.left + block.right * scaleX,
        destination.top + block.bottom * scaleY,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OcrBoxPainter oldDelegate) =>
      oldDelegate.evidence != evidence;
}
