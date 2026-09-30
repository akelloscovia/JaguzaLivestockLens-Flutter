import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jaguza/models/capture_evidence.dart';
import 'package:jaguza/services/capture_repository.dart';
import 'package:jaguza/services/upload_service.dart';

void main() {
  final evidence = CaptureEvidence(
    id: 'capture-1',
    capturedAt: DateTime.utc(2026, 9, 29),
    imageBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]),
    imageWidth: 640,
    imageHeight: 480,
    tagCropBytes: Uint8List.fromList([4, 5]),
    tagCropWidth: 120,
    tagCropHeight: 48,
    tagRegion: const TagRegion(left: 100, top: 80, right: 220, bottom: 128),
    tagTexts: const ['TAG 4821'],
    tagDetections: const [
      TagDetectionEvidence(
        left: 100,
        top: 80,
        right: 220,
        bottom: 128,
        confidence: 0.93,
        label: 'ear_tag',
      ),
    ],
    annotatedImageBytes: Uint8List.fromList([6, 7]),
    ocrText: 'TAG 4821',
    tagConfidence: 0.92,
    blocks: const [
      OcrBlockEvidence(
        text: 'TAG 4821',
        left: 12,
        top: 24,
        right: 155,
        bottom: 61,
        confidence: 0.92,
        languages: ['Latin'],
      ),
    ],
  );

  test('OCR evidence JSON includes text and image-space bounds', () {
    final json = evidence.toOcrJson();
    final ocr = json['ocr']! as Map<String, Object?>;
    final blocks = ocr['blocks']! as List<Map<String, Object?>>;
    final bounds = blocks.single['bounding_box']! as Map<String, Object?>;

    expect(ocr['text'], 'TAG 4821');
    expect(ocr['tag_id'], 'TAG 4821');
    expect(json['tag_detections'], hasLength(1));
    expect(bounds['left'], 12);
    expect(bounds['bottom'], 61);
    expect(blocks.single['confidence'], 0.92);
  });

  test('detects the original image media type from its bytes', () {
    final pngEvidence = CaptureEvidence(
      id: 'png-capture',
      capturedAt: DateTime.utc(2026, 9, 29),
      imageBytes: Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]),
      imageWidth: 640,
      imageHeight: 480,
      ocrText: '',
      blocks: const [],
    );

    expect(pngEvidence.imageMimeType, 'image/png');
    expect(pngEvidence.imageFileExtension, 'png');
    expect(
      (pngEvidence.toOcrJson()['image']! as Map<String, Object?>)['mime_type'],
      'image/png',
    );
  });

  test('unconfigured endpoint leaves upload pending', () async {
    final service = UploadService(
      client: MockClient((request) async => fail('Unexpected request')),
      endpoint: '',
    );

    final result = await service.upload(evidence);

    expect(result.status, UploadStatus.pending);
    expect(result.message, contains('UPLOAD_API_URL'));
    service.close();
  });

  test('upload sends original JPEG and OCR JSON as multipart fields', () async {
    final client = MockClient((request) async {
      expect(request.url, Uri.parse('https://api.example.test/captures'));
      expect(request, isA<http.Request>());
      final uploadRequest = request;
      expect(
        uploadRequest.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      final multipartBody = String.fromCharCodes(uploadRequest.bodyBytes);
      expect(
        multipartBody,
        contains('name="image"; filename="capture_capture-1.jpg"'),
      );
      expect(multipartBody, contains('content-type: image/jpeg'));
      expect(multipartBody, contains('name="ocr_json"'));
      expect(multipartBody, contains('"capture_id":"capture-1"'));
      expect(multipartBody, contains('"tag_id":"TAG 4821"'));
      expect(multipartBody, contains('"text":"TAG 4821"'));
      expect(multipartBody, contains(String.fromCharCodes([1, 2, 3])));
      expect(
        multipartBody,
        contains('name="tag_crop"; filename="tag_crop_capture-1.png"'),
      );
      expect(multipartBody, contains('content-type: image/png'));
      expect(multipartBody, contains(String.fromCharCodes([4, 5])));
      expect(
        multipartBody,
        contains('name="annotated_image"; filename="annotated_capture-1.png"'),
      );
      expect(multipartBody, contains(String.fromCharCodes([6, 7])));
      return http.Response('accepted', 201);
    });
    final service = UploadService(
      client: client,
      endpoint: 'https://api.example.test/captures',
    );

    final result = await service.upload(evidence);

    expect(result.status, UploadStatus.success, reason: result.message);
    expect(result.message, contains('201'));
    service.close();
  });

  test('upload preserves PNG file type in multipart metadata', () async {
    final pngEvidence = CaptureEvidence(
      id: 'png-capture',
      capturedAt: DateTime.utc(2026, 9, 29),
      imageBytes: Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]),
      imageWidth: 640,
      imageHeight: 480,
      ocrText: '',
      blocks: const [],
    );
    final client = MockClient((request) async {
      final multipartBody = String.fromCharCodes(request.bodyBytes);
      expect(
        multipartBody,
        contains('name="image"; filename="capture_png-capture.png"'),
      );
      expect(multipartBody, contains('content-type: image/png'));
      expect(multipartBody, contains('"mime_type":"image/png"'));
      return http.Response('accepted', 201);
    });
    final service = UploadService(
      client: client,
      endpoint: 'https://api.example.test/captures',
    );

    final result = await service.upload(pngEvidence);

    expect(result.status, UploadStatus.success, reason: result.message);
    service.close();
  });

  test(
    'capture repository restores original, tag crop, OCR, and upload state',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'jaguza_capture_test_',
      );
      try {
        final repository = CaptureRepository(rootDirectory: temporaryDirectory);
        await repository.save(evidence);

        final restored = await repository.loadLatest();

        expect(restored, hasLength(1));
        expect(restored.single.imageBytes, evidence.imageBytes);
        expect(restored.single.tagCropBytes, evidence.tagCropBytes);
        expect(
          restored.single.annotatedImageBytes,
          evidence.annotatedImageBytes,
        );
        expect(restored.single.tagRegion?.left, 100);
        expect(restored.single.tagTexts, ['TAG 4821']);
        expect(restored.single.tagDetections.single.confidence, 0.93);
        expect(restored.single.ocrText, 'TAG 4821');
        expect(restored.single.tagConfidence, 0.92);
        expect(restored.single.blocks.single.left, 12);
      } finally {
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );
}
