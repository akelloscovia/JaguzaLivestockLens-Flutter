import 'package:flutter_test/flutter_test.dart';
import 'package:jaguza/screens/camera_screen.dart';

void main() {
  group('gallery media validation', () {
    test('accepts image mime types', () {
      expect(isSupportedGalleryMediaType('image/jpeg'), isTrue);
      expect(isSupportedGalleryMediaType('image/png'), isTrue);
    });

    test('rejects unsupported video files with a clear message', () {
      expect(isSupportedGalleryMediaType('video/mp4'), isFalse);
      expect(
        galleryMediaSupportMessage('video/mp4'),
        'Video uploads are not supported yet. Please select a photo.',
      );
    });
  });
}
