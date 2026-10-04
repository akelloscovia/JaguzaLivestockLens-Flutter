import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EarTagDetection {
  const EarTagDetection({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence,
    this.label,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double? confidence;
  final String? label;

  double get width => right - left;
  double get height => bottom - top;

  Map<String, Object?> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'confidence': confidence,
    'label': label,
  };

  factory EarTagDetection.fromJson(Map<String, dynamic> json) {
    final bounds = _mapValue(
      json['bounding_box'] ?? json['bbox'] ?? json['box'],
    );
    final source = bounds ?? json;
    final left = _number(source['left']);
    final top = _number(source['top']);
    final right = _number(source['right']);
    final bottom = _number(source['bottom']);
    final x = _number(source['x']);
    final y = _number(source['y']);
    final width = _number(source['width'] ?? source['w']);
    final height = _number(source['height'] ?? source['h']);

    if (left != null && top != null && right != null && bottom != null) {
      return EarTagDetection(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        confidence: _number(json['confidence'] ?? json['score']),
        label: _string(json['class'] ?? json['label'] ?? json['tag']),
      );
    }
    if (x != null && y != null && width != null && height != null) {
      return EarTagDetection(
        left: x - width / 2,
        top: y - height / 2,
        right: x + width / 2,
        bottom: y + height / 2,
        confidence: _number(json['confidence'] ?? json['score']),
        label: _string(json['class'] ?? json['label'] ?? json['tag']),
      );
    }
    throw const FormatException('An ear-tag detection has no usable box.');
  }
}

class EarTagReadResult {
  const EarTagReadResult({
    required this.tagTexts,
    required this.detections,
    this.outputImageBytes,
    this.tagNumber,
    this.tagColor,
  });

  final List<String> tagTexts;
  final List<EarTagDetection> detections;
  final Uint8List? outputImageBytes;
  final String? tagNumber;
  final String? tagColor;

  String? get primaryTagText => tagTexts.isEmpty ? null : tagTexts.first;

  EarTagDetection? get primaryDetection {
    if (detections.isEmpty) return null;
    final sorted = [...detections]
      ..sort((left, right) {
        return (right.confidence ?? -1).compareTo(left.confidence ?? -1);
      });
    return sorted.first;
  }
}

class EarTagReader {
  EarTagReader({http.Client? client, String? endpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? configuredEndpoint;

  static const configuredEndpoint = String.fromEnvironment(
    'EAR_TAG_API_URL',
    defaultValue: 'http://143.198.174.35:9062/api/read-ear-tag',
  );

  final http.Client _client;
  final String _endpoint;

  bool get isConfigured => _endpoint.trim().isNotEmpty;

  Future<EarTagReadResult> readEarTag(Uint8List imageBytes) async {
    if (!isConfigured) {
      throw const EarTagReaderException(
        'Configure EAR_TAG_API_URL to enable automatic tag detection.',
      );
    }
    final uri = Uri.tryParse(_endpoint);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const EarTagReaderException(
        'EAR_TAG_API_URL must be a valid HTTP or HTTPS URL.',
      );
    }

    final stopwatch = Stopwatch()..start();
    debugPrint('[EarTag] POST $uri image=${imageBytes.length}B (multipart)');
    final http.Response response;
    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'imageFile',
            imageBytes,
            filename: 'ear_tag.jpg',
          ),
        );
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 90));
      response = await http.Response.fromStream(streamed);
    } catch (error) {
      debugPrint('[EarTag] failed after ${stopwatch.elapsedMilliseconds}ms: $error');
      rethrow;
    }
    debugPrint(
      '[EarTag] HTTP ${response.statusCode} in ${stopwatch.elapsedMilliseconds}ms '
      'response=${response.bodyBytes.length}B',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EarTagReaderException(
        'Ear-tag reading failed (HTTP ${response.statusCode}): '
        '${_shorten(response.body)}',
      );
    }

    final decoded = jsonDecode(response.body);
    final body = _mapValue(decoded);
    if (body == null) {
      throw const EarTagReaderException(
        'The ear-tag API response is not an object.',
      );
    }

    final roboflow = _mapValue(body['roboflow_reading']);
    final outputs = roboflow?['outputs'];
    final first = outputs is List && outputs.isNotEmpty
        ? _mapValue(outputs.first)
        : null;

    final openai = _mapValue(body['openai_reading']);

    final detectionTexts = first == null
        ? const <String>[]
        : _parseTexts(first['tag_text']);
    final openaiText = _string(openai?['tag_text'])?.trim();
    final texts = [
      if (openaiText != null && openaiText.isNotEmpty) openaiText,
      ...detectionTexts.where((text) => text != openaiText),
    ];
    final detections = first == null
        ? const <EarTagDetection>[]
        : _parseDetections(first['tag_detections']);
    if (texts.isEmpty && detections.isEmpty) {
      throw const EarTagReaderException(
        'The ear-tag API returned no tag text or detections.',
      );
    }

    final pictures = _mapValue(body['pictures']);
    final annotatedUrl =
        _string(pictures?['annotated']) ?? _string(pictures?['original']);
    final outputImageBytes = await _fetchImage(annotatedUrl);

    return EarTagReadResult(
      tagTexts: texts,
      detections: detections,
      outputImageBytes: outputImageBytes,
      tagNumber: _string(openai?['tag_number']),
      tagColor: _string(openai?['tag_color']),
    );
  }

  Future<Uint8List?> _fetchImage(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return response.bodyBytes;
    } catch (error) {
      debugPrint('[EarTag] failed to fetch picture $uri: $error');
      return null;
    }
  }

  void close() => _client.close();

  static List<String> _parseTexts(Object? value) {
    final values = value is List ? value : [value];
    return values
        .whereType<String>()
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
  }

  static List<EarTagDetection> _parseDetections(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const EarTagReaderException(
        'The ear-tag API detections value is not a list.',
      );
    }
    return value
        .map(_mapValue)
        .whereType<Map<String, dynamic>>()
        .map(EarTagDetection.fromJson)
        .toList(growable: false);
  }

  static String _shorten(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length > 300
        ? '${normalized.substring(0, 297)}...'
        : normalized;
  }
}

class EarTagReaderException implements Exception {
  const EarTagReaderException(this.message);

  final String message;

  @override
  String toString() => message;
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  return null;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

String? _string(Object? value) => value is String ? value : null;
