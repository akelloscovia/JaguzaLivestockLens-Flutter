import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/capture_evidence.dart';

class OcrService {
  Future<OcrResult> recognize({required String imagePath}) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
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
      return OcrResult(text: recognized.text, blocks: blocks);
    } finally {
      await recognizer.close();
    }
  }
}
