import '../models/capture_evidence.dart';
import 'tag_cropper.dart';

class OcrService {
  Future<OcrResult> recognize({required TagCrop crop}) {
    throw UnsupportedError('On-device OCR is supported on Android and iOS.');
  }
}
