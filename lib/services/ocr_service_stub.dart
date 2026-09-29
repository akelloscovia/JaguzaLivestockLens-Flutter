import '../models/capture_evidence.dart';

class OcrService {
  Future<OcrResult> recognize({required String imagePath}) {
    throw UnsupportedError('On-device OCR is supported on Android and iOS.');
  }
}
