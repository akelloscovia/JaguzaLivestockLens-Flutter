import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../models/capture_evidence.dart';
import '../services/image_dimensions.dart';
import '../services/ocr_service.dart';
import '../services/upload_service.dart';
import '../widgets/ocr_image_review.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.onEvidenceChanged,
    required this.uploadService,
  });

  final ValueChanged<CaptureEvidence> onEvidenceChanged;
  final UploadService uploadService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Uint8List? _capturedPhoto;
  CaptureEvidence? _evidence;
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
    final onEvidenceChanged = widget.onEvidenceChanged;
    setState(() {
      _isCapturing = true;
      _isProcessing = true;
      _errorMessage = null;
      _processingMessage = 'Capturing original image...';
      _evidence = null;
    });
    try {
      final photo = await controller.takePicture();
      final photoBytes = await photo.readAsBytes();
      if (mounted) {
        setState(() {
          _capturedPhoto = photoBytes;
          _processingMessage = 'Reading visible text...';
        });
      }
      final dimensions = await readImageDimensions(photoBytes);
      OcrResult? result;
      String? ocrError;
      try {
        result = await _ocrService.recognize(imagePath: photo.path);
      } catch (error) {
        ocrError = error is UnsupportedError
            ? error.message
            : 'Text recognition failed: $error';
      }

      final evidence = CaptureEvidence(
        id: DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
        capturedAt: DateTime.now().toUtc(),
        imageBytes: photoBytes,
        imageWidth: dimensions.width,
        imageHeight: dimensions.height,
        ocrText: result?.text ?? '',
        blocks: result?.blocks ?? const [],
        ocrError: ocrError,
      );
      onEvidenceChanged(evidence);
      if (mounted) {
        setState(() {
          _evidence = evidence;
          _isProcessing = false;
          _processingMessage = 'Uploading image and OCR evidence...';
        });
      }
      await _uploadEvidence(evidence, onEvidenceChanged);
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

  Future<void> _uploadEvidence(
    CaptureEvidence evidence,
    ValueChanged<CaptureEvidence> onEvidenceChanged,
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
    onEvidenceChanged(uploading);
    final result = await widget.uploadService.upload(evidence);
    final updated = evidence.copyWith(
      uploadStatus: result.status,
      uploadMessage: result.message,
    );
    if (mounted) {
      setState(() {
        _evidence = updated;
        _isUploading = false;
      });
    }
    onEvidenceChanged(updated);
  }

  void _retakePhoto() {
    setState(() {
      _capturedPhoto = null;
      _evidence = null;
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
            else
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
                      onPressed: evidence == null || _isUploading
                          ? null
                          : _retryUpload,
                      icon: Icon(
                        evidence?.uploadStatus == UploadStatus.success
                            ? Icons.check
                            : Icons.cloud_upload_outlined,
                      ),
                      label: Text(
                        evidence?.uploadStatus == UploadStatus.success
                            ? 'Uploaded'
                            : 'Retry upload',
                      ),
                    ),
                  ),
                ],
              ),
            if (evidence != null) ...[
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
