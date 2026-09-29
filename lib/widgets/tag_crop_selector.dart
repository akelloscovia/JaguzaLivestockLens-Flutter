import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/capture_evidence.dart';

class TagCropSelector extends StatefulWidget {
  const TagCropSelector({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.onRegionChanged,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final ValueChanged<TagRegion?> onRegionChanged;

  @override
  State<TagCropSelector> createState() => _TagCropSelectorState();
}

class _TagCropSelectorState extends State<TagCropSelector> {
  TagRegion? _region;
  Offset? _dragStart;

  Offset? _toImagePoint(Offset point, Size viewport) {
    final imageSize = Size(
      widget.imageWidth.toDouble(),
      widget.imageHeight.toDouble(),
    );
    final fitted = applyBoxFit(BoxFit.contain, imageSize, viewport);
    final imageRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & viewport,
    );
    if (!imageRect.inflate(1).contains(point)) return null;
    final x = ((point.dx - imageRect.left) / imageRect.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final y = ((point.dy - imageRect.top) / imageRect.height)
        .clamp(0.0, 1.0)
        .toDouble();
    return Offset(x * widget.imageWidth, y * widget.imageHeight);
  }

  TagRegion _regionBetween(Offset first, Offset second) => TagRegion(
    left: first.dx < second.dx ? first.dx : second.dx,
    top: first.dy < second.dy ? first.dy : second.dy,
    right: first.dx > second.dx ? first.dx : second.dx,
    bottom: first.dy > second.dy ? first.dy : second.dy,
  );

  void _updateSelection(Offset point) {
    final start = _dragStart;
    if (start == null) return;
    setState(() => _region = _regionBetween(start, point));
    widget.onRegionChanged(_region);
  }

  void _finishSelection() {
    final region = _region;
    if (region != null && (region.width < 24 || region.height < 24)) {
      setState(() => _region = null);
      widget.onRegionChanged(null);
    }
    _dragStart = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            final point = _toImagePoint(details.localPosition, viewport);
            if (point == null) return;
            setState(() {
              _dragStart = point;
              _region = _regionBetween(point, point);
            });
          },
          onPanUpdate: (details) {
            final point = _toImagePoint(details.localPosition, viewport);
            if (point != null) _updateSelection(point);
          },
          onPanEnd: (_) => _finishSelection(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: const Color(0xFF202923),
                child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
              ),
              CustomPaint(
                foregroundPainter: _SelectionPainter(
                  imageWidth: widget.imageWidth,
                  imageHeight: widget.imageHeight,
                  region: _region,
                ),
              ),
              if (_region == null)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Tag area not selected',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.imageWidth,
    required this.imageHeight,
    required this.region,
  });

  final int imageWidth;
  final int imageHeight;
  final TagRegion? region;

  @override
  void paint(Canvas canvas, Size size) {
    final selection = region;
    if (selection == null || imageWidth <= 0 || imageHeight <= 0) return;
    final sourceSize = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final scaleX = destination.width / sourceSize.width;
    final scaleY = destination.height / sourceSize.height;
    final rect = Rect.fromLTRB(
      destination.left + selection.left * scaleX,
      destination.top + selection.top * scaleY,
      destination.left + selection.right * scaleX,
      destination.top + selection.bottom * scaleY,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFFB9E4A8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter oldDelegate) =>
      oldDelegate.region != region ||
      oldDelegate.imageWidth != imageWidth ||
      oldDelegate.imageHeight != imageHeight;
}
