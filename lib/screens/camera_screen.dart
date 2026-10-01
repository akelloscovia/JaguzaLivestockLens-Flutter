import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app.dart';
import '../services/gallery_picker.dart';
import '../models/capture_evidence.dart';
import '../services/ear_tag_reader.dart';
import '../services/image_dimensions.dart';
import '../services/ocr_service.dart';
import '../services/tag_cropper.dart';
import '../services/upload_service.dart';
import '../widgets/ocr_image_review.dart';

bool isSupportedGalleryMediaType(String? mimeType) {
  final normalized = mimeType?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return true;
  }
  return normalized.startsWith('image/');
}

String? galleryMediaSupportMessage(String? mimeType) {
  final normalized = mimeType?.trim().toLowerCase();
  if (normalized != null && normalized.startsWith('video/')) {
    return 'Video uploads are not supported yet. Please select a photo.';
  }
  return null;
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.onEvidenceChanged,
    required this.earTagReader,
    required this.uploadService,
  });

  final Future<void> Function(CaptureEvidence) onEvidenceChanged;
  final EarTagReader earTagReader;
  final UploadService uploadService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Uint8List? _capturedPhoto;
  CaptureEvidence? _evidence;
  int? _imageWidth;
  int? _imageHeight;
  String? _captureId;
  String? _errorMessage;
  bool _isInitializing = true;
  bool _isCapturing = false;
  bool _isProcessing = false;
  bool _isUploading = false;
  String _processingMessage = 'Preparing camera...';
  final OcrService _ocrService = OcrService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_retrieveLostPhoto());
    _initializeCamera();
  }

  Future<void> _retrieveLostPhoto() async {
    try {
      final response = await _imagePicker.retrieveLostData();
      if (response.isEmpty) return;
      final files = response.files;
      if (files != null && files.isNotEmpty) {
        await _usePhotoBytes(await files.first.readAsBytes());
      } else if (response.exception != null && mounted) {
        final exception = response.exception;
        if (exception is MissingPluginException) {
          return;
        }
        setState(() {
          _errorMessage =
              'Could not restore selected photo: '
              '$exception';
        });
      }
    } on MissingPluginException {
      return;
    } on PlatformException catch (_) {
      return;
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not restore selected photo: $error',
        );
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera is available.');
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } on CameraException catch (error) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _errorMessage = error.description ?? 'Could not open the camera.';
        _isInitializing = false;
      });
    } catch (_) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not open the camera.';
        _isInitializing = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      _controller = null;
      if (controller != null) unawaited(controller.dispose());
    } else if (state == AppLifecycleState.resumed && _capturedPhoto == null) {
      _initializeCamera();
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
      _evidence = null;
    });
    try {
      final photo = await controller.takePicture();
      final photoBytes = await photo.readAsBytes();
      await _usePhotoBytes(photoBytes);
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.description ?? 'Capture failed.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not process capture: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isProcessing = false;
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _pickPhoto() async {
    if (_isCapturing || _isProcessing) return;
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
      _evidence = null;
    });
    try {
      Uint8List? imageBytes;

      if (kIsWeb) {
        imageBytes = await pickGalleryImageBytes();
      } else {
        final photo = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          requestFullMetadata: false,
        );
        if (photo == null) {
          return;
        }
        imageBytes = await photo.readAsBytes();
      }

      if (imageBytes == null) {
        return;
      }

      await _usePhotoBytes(imageBytes);
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Photo selection is not available on this platform. Please use a supported mobile/web build.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not load photo: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isProcessing = false;
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _usePhotoBytes(Uint8List photoBytes) async {
    final dimensions = await readImageDimensions(photoBytes);
    if (!mounted) return;
    final captureId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    setState(() {
      _capturedPhoto = photoBytes;
      _imageWidth = dimensions.width;
      _imageHeight = dimensions.height;
      _captureId = captureId;
    });
  }

  Future<void> _readTag() async {
    final photo = _capturedPhoto;
    final width = _imageWidth;
    final height = _imageHeight;
    if (photo == null || width == null || height == null) return;
    if (!widget.earTagReader.isConfigured) {
      setState(
        () => _errorMessage =
            'Automatic ear-tag detection is not configured. '
            'Set EAR_TAG_API_URL and try again.',
      );
      return;
    }
    await _readTagWithBackend(
      photo,
      width,
      height,
      _captureId ?? DateTime.now().microsecondsSinceEpoch.toString(),
    );
  }

  Future<void> _readTagWithBackend(
    Uint8List photo,
    int imageWidth,
    int imageHeight,
    String captureId,
  ) async {
    final earTagReader = widget.earTagReader;
    final onEvidenceChanged = widget.onEvidenceChanged;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _processingMessage = 'Detecting tag and reading its text...';
    });
    try {
      final result = await earTagReader.readEarTag(photo);
      final detections = result.detections
          .map((detection) {
            var left = detection.left;
            var top = detection.top;
            var right = detection.right;
            var bottom = detection.bottom;
            if (right <= 1 && bottom <= 1) {
              left *= imageWidth;
              right *= imageWidth;
              top *= imageHeight;
              bottom *= imageHeight;
            }
            left = left.clamp(0, imageWidth).toDouble();
            right = right.clamp(0, imageWidth).toDouble();
            top = top.clamp(0, imageHeight).toDouble();
            bottom = bottom.clamp(0, imageHeight).toDouble();
            return TagDetectionEvidence(
              left: left,
              top: top,
              right: right,
              bottom: bottom,
              confidence: detection.confidence,
              label: detection.label,
            );
          })
          .where(
            (detection) =>
                detection.right > detection.left &&
                detection.bottom > detection.top,
          )
          .toList();
      detections.sort(
        (left, right) =>
            (right.confidence ?? -1).compareTo(left.confidence ?? -1),
      );
      final primaryDetection = detections.isEmpty ? null : detections.first;
      final region = primaryDetection == null
          ? null
          : TagRegion(
              left: primaryDetection.left,
              top: primaryDetection.top,
              right: primaryDetection.right,
              bottom: primaryDetection.bottom,
            );
      TagCrop? crop;
      OcrResult? localResult;
      String? localOcrError;
      if (region != null) {
        crop = await cropTagImage(photo, region);
        if (mounted) {
          setState(
            () => _processingMessage = 'Verifying text on the tag crop...',
          );
        }
        try {
          localResult = await _ocrService.recognize(crop: crop);
        } catch (error) {
          localOcrError = error is UnsupportedError
              ? error.message
              : 'On-device verification failed: $error';
        }
      }
      final tagTexts = result.tagTexts.isNotEmpty
          ? result.tagTexts
          : localResult == null || localResult.text.isEmpty
          ? const <String>[]
          : [localResult.text];
      final evidence = CaptureEvidence(
        id: captureId,
        capturedAt: DateTime.now().toUtc(),
        imageBytes: photo,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        tagCropBytes: crop?.bytes,
        tagCropWidth: crop?.width,
        tagCropHeight: crop?.height,
        tagRegion: region,
        tagTexts: tagTexts,
        tagDetections: detections,
        annotatedImageBytes: result.outputImageBytes,
        ocrText: tagTexts.isEmpty ? '' : tagTexts.first,
        tagConfidence: localResult?.confidence,
        localOcrText: localResult?.text,
        localOcrError: localOcrError,
        blocks: localResult?.blocks ?? const [],
      );
      if (mounted) setState(() => _evidence = evidence);
      await onEvidenceChanged(evidence);
      await _uploadEvidence(evidence, onEvidenceChanged);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Tag API failed: $error');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _uploadEvidence(
    CaptureEvidence evidence,
    Future<void> Function(CaptureEvidence) onEvidenceChanged,
  ) async {
    final uploading = evidence.copyWith(
      uploadStatus: UploadStatus.pending,
      uploadMessage: 'Uploading...',
    );
    if (mounted) {
      setState(() {
        _isUploading = true;
        _processingMessage = 'Uploading image and OCR evidence...';
        _evidence = uploading;
      });
    }
    try {
      await onEvidenceChanged(uploading);
      final result = await widget.uploadService.upload(evidence);
      final updated = evidence.copyWith(
        uploadStatus: result.status,
        uploadMessage: result.message,
      );
      if (mounted) setState(() => _evidence = updated);
      await onEvidenceChanged(updated);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedPhoto = null;
      _evidence = null;
      _imageWidth = null;
      _imageHeight = null;
      _captureId = null;
      _errorMessage = null;
    });
  }

  Future<void> _retryUpload() async {
    final evidence = _evidence;
    if (evidence == null || _isUploading) return;
    await _uploadEvidence(evidence, widget.onEvidenceChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = _capturedPhoto;
    final controller = _controller;
    final evidence = _evidence;

    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFF202923),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: evidence != null
                    ? OcrImageReview(evidence: evidence)
                    : photo != null && _isProcessing
                    ? Image.memory(photo, fit: BoxFit.contain)
                    : photo != null
                    ? Image.memory(photo, fit: BoxFit.contain)
                    : _buildLivePreview(controller),
              ),
            ),
            if (_isProcessing || _isUploading) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Text(_processingMessage)),
                ],
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFF9E3028)),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 18),
            if (photo == null)
              SizedBox(
                height: 84,
                child: Center(
                  child: _isCapturing
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton.outlined(
                              onPressed: _pickPhoto,
                              icon: const Icon(Icons.photo_library_outlined),
                              tooltip: 'Choose an existing photo',
                              style: IconButton.styleFrom(
                                fixedSize: const Size(52, 52),
                              ),
                            ),
                            const SizedBox(width: 18),
                            IconButton.filled(
                              onPressed: controller == null
                                  ? null
                                  : _capturePhoto,
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 30,
                              ),
                              tooltip: 'Capture photo',
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white,
                                fixedSize: const Size(68, 68),
                              ),
                            ),
                          ],
                        ),
                ),
              )
            else if (evidence == null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _retakePhoto,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isProcessing ? null : _readTag,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Detect and read ear tag'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _retakePhoto,
                      icon: const Icon(Icons.refresh),
                      label: const Text('New photo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _isUploading ||
                              evidence.uploadStatus == UploadStatus.success
                          ? null
                          : _retryUpload,
                      icon: Icon(
                        evidence.uploadStatus == UploadStatus.success
                            ? Icons.check
                            : Icons.cloud_upload_outlined,
                      ),
                      label: Text(
                        evidence.uploadStatus == UploadStatus.success
                            ? 'Uploaded'
                            : 'Retry upload',
                      ),
                    ),
                  ),
                ],
              ),
            if (evidence != null) ...[
              if (evidence.tagCropBytes != null) ...[
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tag crop'),
                ),
                const SizedBox(height: 6),
                TagCropReview(evidence: evidence, height: 110),
              ],
              const SizedBox(height: 10),
              _UploadStatusLine(evidence: evidence),
              if (evidence.ocrError != null) ...[
                const SizedBox(height: 6),
                Text(
                  'OCR: ${evidence.ocrError}',
                  style: const TextStyle(color: Color(0xFF9E3028)),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 6),
              SelectableText(
                evidence.ocrText.isEmpty
                    ? 'No text detected.'
                    : evidence.ocrText,
                maxLines: 3,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (evidence.tagTexts.length > 1) ...[
                const SizedBox(height: 4),
                Text(
                  'Other readings: ${evidence.tagTexts.skip(1).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (evidence.tagDetections.isNotEmpty &&
                  evidence.tagDetections.first.confidence != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Tag detection confidence: '
                  '${(evidence.tagDetections.first.confidence! * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (evidence.localOcrText != null &&
                  evidence.localOcrText!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'On-device crop check: ${evidence.localOcrText}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (evidence.localOcrError != null) ...[
                const SizedBox(height: 4),
                Text(
                  'On-device check: ${evidence.localOcrError}',
                  style: const TextStyle(color: Color(0xFF9E3028)),
                  textAlign: TextAlign.center,
                ),
              ],
              if (evidence.tagConfidence != null) ...[
                const SizedBox(height: 4),
                Text(
                  'On-device OCR confidence: ${(evidence.tagConfidence! * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLivePreview(CameraController? controller) {
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Icon(
          Icons.no_photography_outlined,
          color: Colors.white,
          size: 36,
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),
    );
  }
}

class _UploadStatusLine extends StatelessWidget {
  const _UploadStatusLine({required this.evidence});

  final CaptureEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final color = switch (evidence.uploadStatus) {
      UploadStatus.success => AppColors.accent,
      UploadStatus.failure => const Color(0xFF9E3028),
      UploadStatus.pending => AppColors.muted,
    };
    return Text(
      '${evidence.uploadStatus.name.toUpperCase()}: ${evidence.uploadMessage ?? ''}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      textAlign: TextAlign.center,
    );
  }
}
