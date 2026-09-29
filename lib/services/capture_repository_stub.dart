import '../models/capture_evidence.dart';

class CaptureRepository {
  CaptureRepository({Object? rootDirectory});

  final List<CaptureEvidence> _captures = [];

  Future<List<CaptureEvidence>> loadLatest({int limit = 5}) async =>
      List.unmodifiable(_captures.take(limit));

  Future<void> save(CaptureEvidence evidence) async {
    _captures.removeWhere((item) => item.id == evidence.id);
    _captures.insert(0, evidence);
    if (_captures.length > 5) _captures.removeRange(5, _captures.length);
  }
}
