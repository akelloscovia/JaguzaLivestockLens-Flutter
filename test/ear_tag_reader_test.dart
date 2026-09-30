import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jaguza/services/ear_tag_reader.dart';

void main() {
  test(
    'sends imageBase64 and parses text, detection, and output image',
    () async {
      final sourceImage = Uint8List.fromList([1, 2, 3, 4]);
      final annotatedImage = Uint8List.fromList([9, 8, 7]);
      final client = MockClient((request) async {
        expect(
          request.url,
          Uri.parse('https://api.example.test/api/read-ear-tag'),
        );
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers.containsKey('authorization'), isFalse);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['imageBase64'], base64Encode(sourceImage));
        return http.Response(
          jsonEncode({
            'outputs': [
              {
                'tag_text': ['BLITZ 1042'],
                'tag_detections': [
                  {
                    'x': 50,
                    'y': 40,
                    'width': 20,
                    'height': 12,
                    'confidence': 0.93,
                    'class': 'ear_tag',
                  },
                ],
                'output_image': base64Encode(annotatedImage),
              },
            ],
          }),
          200,
        );
      });
      final reader = EarTagReader(
        client: client,
        endpoint: 'https://api.example.test/api/read-ear-tag',
      );

      final result = await reader.readEarTag(sourceImage);

      expect(result.primaryTagText, 'BLITZ 1042');
      expect(result.primaryDetection?.left, 40);
      expect(result.primaryDetection?.top, 34);
      expect(result.primaryDetection?.right, 60);
      expect(result.primaryDetection?.bottom, 46);
      expect(result.primaryDetection?.confidence, 0.93);
      expect(result.outputImageBytes, annotatedImage);
      reader.close();
    },
  );

  test('reports backend errors with status and response text', () async {
    final reader = EarTagReader(
      client: MockClient((request) async => http.Response('bad API key', 401)),
      endpoint: 'https://api.example.test/api/read-ear-tag',
    );

    await expectLater(
      reader.readEarTag(Uint8List.fromList([1])),
      throwsA(
        isA<EarTagReaderException>()
            .having((error) => error.message, 'message', contains('HTTP 401'))
            .having(
              (error) => error.message,
              'message',
              contains('bad API key'),
            ),
      ),
    );
    reader.close();
  });

  test('requires an API URL configuration', () async {
    final reader = EarTagReader(
      client: MockClient((request) async => fail('Unexpected request')),
      endpoint: '',
    );

    await expectLater(
      reader.readEarTag(Uint8List.fromList([1])),
      throwsA(isA<EarTagReaderException>()),
    );
    reader.close();
  });
}
