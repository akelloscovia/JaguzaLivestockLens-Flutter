import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../models/capture_evidence.dart';
import '../services/image_dimensions.dart';
import '../services/ocr_service.dart';
import '../services/tag_cropper.dart';
import '../services/upload_service.dart';
import '../widgets/ocr_image_review.dart';
import '../widgets/tag_crop_selector.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.onEvidenceChanged,
    required this.uploadService,
  });

  final Future<void> Function(CaptureEvidence) onEvidenceChanged;
  final UploadService uploadService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Uint8List? _capturedPhoto;
  CaptureEvidence? _evidence;
  TagRegion? _tagRegion;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
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
      final dimensions = await readImageDimensions(photoBytes);
      if (mounted) {
        setState(() {
          _capturedPhoto = photoBytes;
          _imageWidth = dimensions.width;
          _imageHeight = dimensions.height;
          _captureId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
          _tagRegion = null;
        });
      }
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

  Future<void> _readTag() async {
    final photo = _capturedPhoto;
    final region = _tagRegion;
    final width = _imageWidth;
    final height = _imageHeight;
    final captureId = _captureId;
    if (photo == null || region == null || width == null || height == null) {
      return;
    }
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _processingMessage = 'Cropping tag region...';
    });
    try {
      final crop = await cropTagImage(photo, region);
      if (mounted) {
        setState(() => _processingMessage = 'Reading text on tag...');
      }
      OcrResult? result;
      String? ocrError;
      try {
        result = await _ocrService.recognize(crop: crop);
      } catch (error) {
        ocrError = error is UnsupportedError
            ? error.message
            : 'Tag OCR failed: $error';
      }
      final evidence = CaptureEvidence(
        id: captureId ?? DateTime.now().microsecondsSinceEpoch.toString(),
        capturedAt: DateTime.now().toUtc(),
        imageBytes: photo,
        imageWidth: width,
        imageHeight: height,
        tagCropBytes: crop.bytes,
        tagCropWidth: crop.width,
        tagCropHeight: crop.height,
        tagRegion: region,
        ocrText: result?.text ?? '',
        tagConfidence: result?.confidence,
        blocks: result?.blocks ?? const [],
        ocrError: ocrError,
      );
      if (mounted) {
        setState(() {
          _evidence = evidence;
          _isProcessing = false;
          _processingMessage = 'Uploading tag and OCR evidence...';
        });
      }
      await widget.onEvidenceChanged(evidence);
      await _uploadEvidence(evidence, widget.onEvidenceChanged);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not process tag: $error');
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
      _tagRegion = null;
      _imageWidth = null;
      _imageHeight = null;
      _captureId = null;
      _errorMessage = null;
    });
  }

  void _adjustTagRegion() {
    setState(() {
      _evidence = null;
      _tagRegion = null;
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
                    : photo != null &&
                          _imageWidth != null &&
                          _imageHeight != null
                    ? TagCropSelector(
                        imageBytes: photo,
                        imageWidth: _imageWidth!,
                        imageHeight: _imageHeight!,
                        onRegionChanged: (region) =>
                            setState(() => _tagRegion = region),
                      )
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
                height: 76,
                child: Center(
                  child: _isCapturing
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : IconButton.filled(
                          onPressed: controller == null ? null : _capturePhoto,
                          icon: const Icon(Icons.camera_alt_outlined, size: 30),
                          tooltip: 'Capture photo',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            fixedSize: const Size(68, 68),
                          ),
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
                      onPressed: _tagRegion == null || _isProcessing
                          ? null
                          : _readTag,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Read tag'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _adjustTagRegion,
                      icon: const Icon(Icons.crop_free),
                      label: const Text('Adjust box'),
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
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Tag crop'),
              ),
              const SizedBox(height: 6),
              TagCropReview(evidence: evidence, height: 110),
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
              if (evidence.tagConfidence != null) ...[
                const SizedBox(height: 4),
                Text(
                  'OCR confidence: ${(evidence.tagConfidence! * 100).toStringAsFixed(0)}%',
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
