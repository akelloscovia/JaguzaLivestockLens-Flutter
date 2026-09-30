import 'dart:convert';
import 'dart:typed_data';

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
  });

  final List<String> tagTexts;
  final List<EarTagDetection> detections;
  final Uint8List? outputImageBytes;

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

  static const configuredEndpoint = String.fromEnvironment('EAR_TAG_API_URL');

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

    final response = await _client
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'imageBase64': base64Encode(imageBytes)}),
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EarTagReaderException(
        'Ear-tag reading failed (HTTP ${response.statusCode}): '
        '${_shorten(response.body)}',
      );
    }

    final decoded = jsonDecode(response.body);
    final body = _mapValue(decoded);
    final outputs = body?['outputs'];
    if (outputs is! List || outputs.isEmpty) {
      throw const EarTagReaderException(
        'The ear-tag API response contains no outputs.',
      );
    }
    final first = _mapValue(outputs.first);
    if (first == null) {
      throw const EarTagReaderException(
        'The first ear-tag API output is not an object.',
      );
    }

    final texts = _parseTexts(first['tag_text']);
    final detections = _parseDetections(first['tag_detections']);
    if (texts.isEmpty && detections.isEmpty) {
      throw const EarTagReaderException(
        'The ear-tag API returned no tag text or detections.',
      );
    }
    return EarTagReadResult(
      tagTexts: texts,
      detections: detections,
      outputImageBytes: _parseOutputImage(first['output_image']),
    );
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

  static Uint8List? _parseOutputImage(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final raw = value.trim();
    final comma = raw.indexOf(',');
    final base64Value = raw.startsWith('data:') && comma >= 0
        ? raw.substring(comma + 1)
        : raw;
    try {
      return base64Decode(base64Value);
    } on FormatException {
      return null;
    }
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
