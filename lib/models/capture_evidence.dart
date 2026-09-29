import 'dart:typed_data';

enum UploadStatus { pending, success, failure }

class TagRegion {
  const TagRegion({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  Map<String, Object?> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory TagRegion.fromJson(Map<String, dynamic> json) => TagRegion(
    left: (json['left'] as num).toDouble(),
    top: (json['top'] as num).toDouble(),
    right: (json['right'] as num).toDouble(),
    bottom: (json['bottom'] as num).toDouble(),
  );
}

class OcrResult {
  const OcrResult({required this.text, required this.blocks, this.confidence});

  final String text;
  final List<OcrBlockEvidence> blocks;
  final double? confidence;
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

  factory OcrBlockEvidence.fromJson(Map<String, dynamic> json) {
    final bounds = json['bounding_box'] as Map<String, dynamic>;
    return OcrBlockEvidence(
      text: json['text'] as String? ?? '',
      left: (bounds['left'] as num).toDouble(),
      top: (bounds['top'] as num).toDouble(),
      right: (bounds['right'] as num).toDouble(),
      bottom: (bounds['bottom'] as num).toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      languages: (json['languages'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }
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
    this.tagCropBytes,
    this.tagCropWidth,
    this.tagCropHeight,
    this.tagRegion,
    this.tagConfidence,
    this.ocrError,
    this.uploadStatus = UploadStatus.pending,
    this.uploadMessage = 'Waiting to upload.',
  });

  final String id;
  final DateTime capturedAt;
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final Uint8List? tagCropBytes;
  final int? tagCropWidth;
  final int? tagCropHeight;
  final TagRegion? tagRegion;
  final String ocrText;
  final double? tagConfidence;
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
    tagCropBytes: tagCropBytes,
    tagCropWidth: tagCropWidth,
    tagCropHeight: tagCropHeight,
    tagRegion: tagRegion,
    ocrText: ocrText,
    tagConfidence: tagConfidence,
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
    'tag_region': tagRegion?.toJson(),
    'tag_crop': tagCropBytes == null
        ? null
        : {
            'width': tagCropWidth,
            'height': tagCropHeight,
            'mime_type': 'image/png',
          },
    'ocr': {
      'engine': 'google_ml_kit_text_recognition',
      'tag_id': ocrText,
      'text': ocrText,
      'confidence': tagConfidence,
      'error': ocrError,
      'blocks': blocks.map((block) => block.toJson()).toList(),
    },
  };

  Map<String, Object?> toStorageJson() => {
    'id': id,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'image_width': imageWidth,
    'image_height': imageHeight,
    'tag_crop_width': tagCropWidth,
    'tag_crop_height': tagCropHeight,
    'tag_region': tagRegion?.toJson(),
    'tag_text': ocrText,
    'tag_confidence': tagConfidence,
    'ocr_error': ocrError,
    'blocks': blocks.map((block) => block.toJson()).toList(),
    'upload_status': uploadStatus.name,
    'upload_message': uploadMessage,
  };

  factory CaptureEvidence.fromStorageJson({
    required Map<String, dynamic> json,
    required Uint8List imageBytes,
    required Uint8List tagCropBytes,
  }) => CaptureEvidence(
    id: json['id'] as String,
    capturedAt: DateTime.parse(json['captured_at'] as String),
    imageBytes: imageBytes,
    imageWidth: (json['image_width'] as num).toInt(),
    imageHeight: (json['image_height'] as num).toInt(),
    tagCropBytes: tagCropBytes,
    tagCropWidth: (json['tag_crop_width'] as num?)?.toInt(),
    tagCropHeight: (json['tag_crop_height'] as num?)?.toInt(),
    tagRegion: json['tag_region'] == null
        ? null
        : TagRegion.fromJson(json['tag_region'] as Map<String, dynamic>),
    ocrText: json['tag_text'] as String? ?? '',
    tagConfidence: (json['tag_confidence'] as num?)?.toDouble(),
    ocrError: json['ocr_error'] as String?,
    blocks: (json['blocks'] as List<dynamic>? ?? const [])
        .map((item) => OcrBlockEvidence.fromJson(item as Map<String, dynamic>))
        .toList(),
    uploadStatus: UploadStatus.values.byName(
      json['upload_status'] as String? ?? UploadStatus.pending.name,
    ),
    uploadMessage: json['upload_message'] as String?,
  );
}
