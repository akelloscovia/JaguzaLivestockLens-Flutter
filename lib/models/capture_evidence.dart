import 'dart:typed_data';

enum UploadStatus { pending, success, failure }

class OcrResult {
  const OcrResult({required this.text, required this.blocks});

  final String text;
  final List<OcrBlockEvidence> blocks;
}

class OcrBlockEvidence {
  const OcrBlockEvidence({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence,
    this.languages = const [],
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double? confidence;
  final List<String> languages;

  Map<String, Object?> toJson() => {
    'text': text,
    'bounding_box': {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    },
    'confidence': confidence,
    'languages': languages,
  };
}

class CaptureEvidence {
  const CaptureEvidence({
    required this.id,
    required this.capturedAt,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.ocrText,
    required this.blocks,
    this.ocrError,
    this.uploadStatus = UploadStatus.pending,
    this.uploadMessage = 'Waiting to upload.',
  });

  final String id;
  final DateTime capturedAt;
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final String ocrText;
  final List<OcrBlockEvidence> blocks;
  final String? ocrError;
  final UploadStatus uploadStatus;
  final String? uploadMessage;

  CaptureEvidence copyWith({
    UploadStatus? uploadStatus,
    String? uploadMessage,
  }) => CaptureEvidence(
    id: id,
    capturedAt: capturedAt,
    imageBytes: imageBytes,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    ocrText: ocrText,
    blocks: blocks,
    ocrError: ocrError,
    uploadStatus: uploadStatus ?? this.uploadStatus,
    uploadMessage: uploadMessage ?? this.uploadMessage,
  );

  Map<String, Object?> toOcrJson() => {
    'schema_version': 1,
    'capture_id': id,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'image': {
      'width': imageWidth,
      'height': imageHeight,
      'mime_type': 'image/jpeg',
    },
    'ocr': {
      'engine': 'google_ml_kit_text_recognition',
      'text': ocrText,
      'error': ocrError,
      'blocks': blocks.map((block) => block.toJson()).toList(),
    },
  };
}
