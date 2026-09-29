import 'dart:typed_data';
import 'dart:ui' as ui;

class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;
}

Future<ImageDimensions> readImageDimensions(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final dimensions = ImageDimensions(frame.image.width, frame.image.height);
    frame.image.dispose();
    return dimensions;
  } finally {
    codec.dispose();
  }
}
