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
          foregroundPainter: _TagRegionPainter(evidence: evidence),
          child: ColoredBox(
            color: AppColors.ink,
            child: Image.memory(evidence.imageBytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class TagCropReview extends StatelessWidget {
  const TagCropReview({super.key, required this.evidence, this.height = 160});

  final CaptureEvidence evidence;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bytes = evidence.tagCropBytes;
    if (bytes == null) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          foregroundPainter: _CropOcrBoxPainter(evidence: evidence),
          child: ColoredBox(
            color: AppColors.ink,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _TagRegionPainter extends CustomPainter {
  _TagRegionPainter({required this.evidence});

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

    final region = evidence.tagRegion;
    if (region == null) return;
    final rect = Rect.fromLTRB(
      destination.left + region.left * scaleX,
      destination.top + region.top * scaleY,
      destination.left + region.right * scaleX,
      destination.top + region.bottom * scaleY,
    );
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _TagRegionPainter oldDelegate) =>
      oldDelegate.evidence != evidence;
}

class _CropOcrBoxPainter extends CustomPainter {
  _CropOcrBoxPainter({required this.evidence});

  final CaptureEvidence evidence;

  @override
  void paint(Canvas canvas, Size size) {
    final cropWidth = evidence.tagCropWidth;
    final cropHeight = evidence.tagCropHeight;
    if (cropWidth == null ||
        cropHeight == null ||
        cropWidth <= 0 ||
        cropHeight <= 0) {
      return;
    }
    final sourceSize = Size(cropWidth.toDouble(), cropHeight.toDouble());
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
      canvas.drawRect(
        Rect.fromLTRB(
          destination.left + block.left * scaleX,
          destination.top + block.top * scaleY,
          destination.left + block.right * scaleX,
          destination.top + block.bottom * scaleY,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOcrBoxPainter oldDelegate) =>
      oldDelegate.evidence != evidence;
}
