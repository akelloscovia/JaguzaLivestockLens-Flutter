import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jaguza/models/capture_evidence.dart';
import 'package:jaguza/services/image_dimensions.dart';
import 'package:jaguza/services/tag_cropper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crop output matches the selected source rectangle', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 12, 10),
      ui.Paint()..color = const ui.Color(0xFF365E47),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(12, 10);
    final imageData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    final crop = await cropTagImage(
      Uint8List.fromList(imageData!.buffer.asUint8List()),
      const TagRegion(left: 2, top: 1, right: 8, bottom: 7),
    );
    final dimensions = await readImageDimensions(crop.bytes);

    expect(crop.width, 6);
    expect(crop.height, 6);
    expect(dimensions.width, 6);
    expect(dimensions.height, 6);
  });
}
