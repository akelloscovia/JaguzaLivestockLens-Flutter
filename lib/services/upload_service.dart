import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/capture_evidence.dart';

class UploadResult {
  const UploadResult({required this.status, required this.message});

  final UploadStatus status;
  final String message;
}

class UploadService {
  UploadService({http.Client? client, String? endpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? configuredEndpoint;

  static const configuredEndpoint = String.fromEnvironment(
    'UPLOAD_API_URL',
    defaultValue: 'http://143.198.174.35:9062/api/uploads',
  );

  final http.Client _client;
  final String _endpoint;

  bool get isConfigured => _endpoint.trim().isNotEmpty;

  Future<UploadResult> upload(CaptureEvidence evidence) async {
    if (!isConfigured) {
      return const UploadResult(
        status: UploadStatus.pending,
        message:
            'Upload endpoint is not configured. Run with --dart-define=UPLOAD_API_URL=<your-url>.',
      );
    }

    final imageMimeType = evidence.imageMimeType;
    final imageFileExtension = evidence.imageFileExtension;
    if (imageMimeType == null || imageFileExtension == null) {
      return const UploadResult(
        status: UploadStatus.failure,
        message: 'The selected image format is not supported for upload.',
      );
    }

    final uri = Uri.tryParse(_endpoint);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return const UploadResult(
        status: UploadStatus.failure,
        message: 'UPLOAD_API_URL must be a valid HTTP or HTTPS URL.',
      );
    }

    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'image',
            evidence.imageBytes,
            filename: 'capture_${evidence.id}.$imageFileExtension',
            contentType: MediaType.parse(imageMimeType),
          ),
        )
        ..fields['ocr_json'] = jsonEncode(evidence.toOcrJson());
      final cropBytes = evidence.tagCropBytes;
      if (cropBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'tag_crop',
            cropBytes,
            filename: 'tag_crop_${evidence.id}.png',
            contentType: MediaType('image', 'png'),
          ),
        );
      }
      final annotatedBytes = evidence.annotatedImageBytes;
      if (annotatedBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'annotated_image',
            annotatedBytes,
            filename: 'annotated_${evidence.id}.png',
            contentType: MediaType('image', 'png'),
          ),
        );
      }
      if (evidence.ocrError != null) {
        request.fields['ocr_error'] = evidence.ocrError!;
      }
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      final responseBody = await response.stream.bytesToString().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return UploadResult(
          status: UploadStatus.success,
          message: responseBody.isEmpty
              ? 'Upload completed (HTTP ${response.statusCode}).'
              : 'Upload completed (HTTP ${response.statusCode}): ${_shorten(responseBody)}',
        );
      }
      return UploadResult(
        status: UploadStatus.failure,
        message:
            'Backend returned HTTP ${response.statusCode}${responseBody.isEmpty ? '.' : ': ${_shorten(responseBody)}'}',
      );
    } catch (error) {
      return UploadResult(
        status: UploadStatus.failure,
        message: 'Upload failed: $error',
      );
    }
  }

  String _shorten(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length > 240
        ? '${normalized.substring(0, 237)}...'
        : normalized;
  }

  void close() => _client.close();
}
