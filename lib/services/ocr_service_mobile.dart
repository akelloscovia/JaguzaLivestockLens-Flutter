import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/capture_evidence.dart';
import 'tag_cropper.dart';

class OcrService {
  Future<OcrResult> recognize({required TagCrop crop}) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final cropFile = File(
      path.join(
        temporaryDirectory.path,
        'tag_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
      ),
    );
    await cropFile.writeAsBytes(crop.bytes, flush: true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(cropFile.path),
      );
      final blocks = recognized.blocks.map((block) {
        final confidences = block.lines
            .map((line) => line.confidence)
            .whereType<double>()
            .toList();
        final confidence = confidences.isEmpty
            ? null
            : confidences.reduce((left, right) => left + right) /
                  confidences.length;
        return OcrBlockEvidence(
          text: block.text,
          left: block.boundingBox.left,
          top: block.boundingBox.top,
          right: block.boundingBox.right,
          bottom: block.boundingBox.bottom,
          confidence: confidence,
          languages: block.recognizedLanguages,
        );
      }).toList();
      final confidences = recognized.blocks
          .expand((block) => block.lines)
          .map((line) => line.confidence)
          .whereType<double>()
          .toList();
      final confidence = confidences.isEmpty
          ? null
          : confidences.reduce((left, right) => left + right) /
                confidences.length;
      return OcrResult(
        text: recognized.text.trim().replaceAll(RegExp(r'\s+'), ' '),
        blocks: blocks,
        confidence: confidence,
      );
    } finally {
      await recognizer.close();
      if (await cropFile.exists()) await cropFile.delete();
    }
  }
}
