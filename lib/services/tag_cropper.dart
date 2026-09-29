import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/capture_evidence.dart';

class TagCrop {
  const TagCrop({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

Future<TagCrop> cropTagImage(Uint8List imageBytes, TagRegion region) async {
  final codec = await ui.instantiateImageCodec(imageBytes);
  ui.Image? sourceImage;
  ui.Image? croppedImage;
  ui.Picture? picture;
  try {
    final frame = await codec.getNextFrame();
    sourceImage = frame.image;
    final sourceWidth = sourceImage.width;
    final sourceHeight = sourceImage.height;
    final left = region.left.floor().clamp(0, sourceWidth - 1);
    final top = region.top.floor().clamp(0, sourceHeight - 1);
    final right = region.right.ceil().clamp(left + 1, sourceWidth);
    final bottom = region.bottom.ceil().clamp(top + 1, sourceHeight);
    final cropWidth = right - left;
    final cropHeight = bottom - top;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      sourceImage,
      ui.Rect.fromLTRB(
        left.toDouble(),
        top.toDouble(),
        right.toDouble(),
        bottom.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, cropWidth.toDouble(), cropHeight.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    picture = recorder.endRecording();
    croppedImage = await picture.toImage(cropWidth, cropHeight);
    final data = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode the tag crop.');
    return TagCrop(
      bytes: data.buffer.asUint8List(),
      width: cropWidth,
      height: cropHeight,
    );
  } finally {
    croppedImage?.dispose();
    picture?.dispose();
    sourceImage?.dispose();
    codec.dispose();
  }
}
