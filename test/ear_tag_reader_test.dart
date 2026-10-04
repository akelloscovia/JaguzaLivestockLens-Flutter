import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jaguza/services/ear_tag_reader.dart';

void main() {
  test(
    'sends imageFile as multipart and parses roboflow/openai response',
    () async {
      final sourceImage = Uint8List.fromList([1, 2, 3, 4]);
      final annotatedImage = Uint8List.fromList([9, 8, 7]);
      final client = MockClient((request) async {
        expect(
          request.url,
          Uri.parse('https://api.example.test/api/read-ear-tag'),
        );
        expect(
          request.headers['content-type'],
          contains('multipart/form-data'),
        );
        expect(request.bodyBytes, containsAllInOrder(sourceImage));
        expect(utf8.decode(request.bodyBytes, allowMalformed: true), contains('imageFile'));

        return http.Response(
          jsonEncode({
            'roboflow_reading': {
              'outputs': [
                {
                  'tag_text': ['SMARTBOW\nEARTAG LIFE\nDE 0773247200'],
                  'tag_detections': [
                    {
                      'x': 50,
                      'y': 40,
                      'width': 20,
                      'height': 12,
                      'confidence': 0.93,
                      'class': 'cattle ear tag',
                    },
                  ],
                },
              ],
            },
            'openai_reading': {
              'tag_text': 'SMARTBOW EARTAG LIFE\nDE 0773247200',
              'tag_number': '0773247200',
              'tag_color': 'yellow',
            },
            'pictures': {
              'original': 'https://pictures.example.test/original.jpg',
              'annotated': 'https://pictures.example.test/annotated.jpg',
            },
          }),
          200,
        );
      });
      final reader = EarTagReader(
        client: ImageFetchingClient(client, annotatedImage),
        endpoint: 'https://api.example.test/api/read-ear-tag',
      );

      final result = await reader.readEarTag(sourceImage);

      expect(result.primaryTagText, 'SMARTBOW EARTAG LIFE\nDE 0773247200');
      expect(result.tagNumber, '0773247200');
      expect(result.tagColor, 'yellow');
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

/// Wraps a [MockClient] so the multipart POST goes through it, while GET
/// requests for the annotated picture return fake image bytes.
class ImageFetchingClient extends http.BaseClient {
  ImageFetchingClient(this._inner, this._imageBytes);

  final http.Client _inner;
  final Uint8List _imageBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET') {
      return http.StreamedResponse(Stream.value(_imageBytes), 200);
    }
    return _inner.send(request);
  }
}
