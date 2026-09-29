import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jaguza/models/capture_evidence.dart';
import 'package:jaguza/services/upload_service.dart';

void main() {
  final evidence = CaptureEvidence(
    id: 'capture-1',
    capturedAt: DateTime.utc(2026, 9, 29),
    imageBytes: Uint8List.fromList([1, 2, 3]),
    imageWidth: 640,
    imageHeight: 480,
    ocrText: 'TAG 4821',
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
    expect(bounds['left'], 12);
    expect(bounds['bottom'], 61);
    expect(blocks.single['confidence'], 0.92);
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
      expect(multipartBody, contains('"text":"TAG 4821"'));
      expect(multipartBody, contains(String.fromCharCodes([1, 2, 3])));
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
}
