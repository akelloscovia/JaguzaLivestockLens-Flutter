import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/capture_evidence.dart';

class CaptureRepository {
  CaptureRepository({Directory? rootDirectory})
    : _providedRootDirectory = rootDirectory;

  final Directory? _providedRootDirectory;

  Future<Directory> _rootDirectory() async {
    final provided = _providedRootDirectory;
    final base = provided ?? await getApplicationDocumentsDirectory();
    final root = Directory(path.join(base.path, 'tag_captures'));
    await root.create(recursive: true);
    return root;
  }

  Future<List<CaptureEvidence>> loadLatest({int limit = 5}) async {
    final root = await _rootDirectory();
    final records = <CaptureEvidence>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      try {
        final manifestFile = File(path.join(entity.path, 'evidence.json'));
        final originalFile = File(path.join(entity.path, 'original.jpg'));
        final cropFile = File(path.join(entity.path, 'tag-crop.png'));
        if (!await manifestFile.exists() || !await originalFile.exists()) {
          continue;
        }
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        records.add(
          CaptureEvidence.fromStorageJson(
            json: json,
            imageBytes: await originalFile.readAsBytes(),
            tagCropBytes: await cropFile.exists()
                ? await cropFile.readAsBytes()
                : Uint8List(0),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    records.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    final retained = records.take(limit).toList();
    await _removeExpired(root, retained);
    return retained;
  }

  Future<void> save(CaptureEvidence evidence) async {
    final root = await _rootDirectory();
    final safeId = evidence.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final directory = Directory(path.join(root.path, safeId));
    await directory.create(recursive: true);
    final originalFile = File(path.join(directory.path, 'original.jpg'));
    final cropFile = File(path.join(directory.path, 'tag-crop.png'));
    if (!await originalFile.exists()) {
      await originalFile.writeAsBytes(evidence.imageBytes, flush: true);
    }
    final cropBytes = evidence.tagCropBytes;
    if (cropBytes != null) {
      await cropFile.writeAsBytes(cropBytes, flush: true);
    }
    await File(
      path.join(directory.path, 'evidence.json'),
    ).writeAsString(jsonEncode(evidence.toStorageJson()), flush: true);
    await loadLatest();
  }

  Future<void> _removeExpired(
    Directory root,
    List<CaptureEvidence> retained,
  ) async {
    final ids = retained.map((item) => item.id).toSet();
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final manifest = File(path.join(entity.path, 'evidence.json'));
      if (!await manifest.exists()) continue;
      try {
        final json = jsonDecode(await manifest.readAsString()) as Map;
        if (!ids.contains(json['id'])) await entity.delete(recursive: true);
      } catch (_) {
        await entity.delete(recursive: true);
      }
    }
  }
}
