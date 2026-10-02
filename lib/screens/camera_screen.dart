import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
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

// Photos are downscaled and recompressed as soon as they are taken so they
// upload quickly to the ear-tag API.
const int _maxImageDimension = 1600;
const double _maxPickerDimension = 1600;
const int _pickerImageQuality = 90;

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

class _CameraScreenState extends State<CameraScreen> {
  Uint8List? _capturedPhoto;
  CaptureEvidence? _evidence;
  int? _imageWidth;
  int? _imageHeight;
  String? _captureId;
  String? _errorMessage;
  bool _isCapturing = false;
  bool _isProcessing = false;
  bool _isUploading = false;
  String _processingMessage = 'Preparing photo...';
  final OcrService _ocrService = OcrService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    unawaited(_retrieveLostPhoto());
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

  Future<void> _capturePhoto() async {
    if (_isCapturing || _isProcessing) return;
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
      _evidence = null;
    });
    try {
      // Hands off to the device's camera app, so this app never opens the
      // camera itself.
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxPickerDimension,
        maxHeight: _maxPickerDimension,
        imageQuality: _pickerImageQuality,
        requestFullMetadata: false,
      );
      if (photo == null) return;
      final cropped = await _cropPhoto(photo.path);
      if (cropped == null) return;
      await _usePhotoBytes(cropped);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = error.message ?? 'Could not open the camera.',
      );
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

  /// Lets the user crop the photo; returns null if they cancel.
  Future<Uint8List?> _cropPhoto(String path) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      // Keep uploads small: full-resolution phone photos take too long to
      // send to the ear-tag API on mobile connections.
      maxWidth: _maxImageDimension,
      maxHeight: _maxImageDimension,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop photo',
          toolbarColor: AppColors.accent,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
      ],
    );
    if (cropped == null) return null;
    return cropped.readAsBytes();
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
          maxWidth: _maxPickerDimension,
          maxHeight: _maxPickerDimension,
          imageQuality: _pickerImageQuality,
          requestFullMetadata: false,
        );
        if (photo == null) {
          return;
        }
        imageBytes = await _cropPhoto(photo.path);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = _capturedPhoto;
    final evidence = _evidence;
    final busy = _isProcessing || _isUploading;

    final Widget content;
    if (evidence != null) {
      content = _ResultView(evidence: evidence);
    } else if (photo != null) {
      content = _PhotoPreview(photo: photo, busy: busy, message: _processingMessage);
    } else {
      content = const _CaptureIntro();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          evidence != null
              ? 'Result'
              : photo != null
              ? 'Review photo'
              : 'Scan ear tag',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    _Banner.error(message: _errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  content,
                ],
              ),
            ),
          ),
          _ActionBar(child: _buildActions(photo, evidence)),
        ],
      ),
    );
  }

  Widget _buildActions(Uint8List? photo, CaptureEvidence? evidence) {
    if (photo == null) {
      if (_isCapturing) {
        return const SizedBox(
          height: 52,
          child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _capturePhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take photo'),
            style: _wideButton,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose from gallery'),
            style: _wideOutlinedButton,
          ),
        ],
      );
    }
    if (evidence == null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isProcessing ? null : _retakePhoto,
              icon: const Icon(Icons.refresh),
              label: const Text('Retake'),
              style: _wideOutlinedButton,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _isProcessing ? null : _readTag,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Read ear tag'),
              style: _wideButton,
            ),
          ),
        ],
      );
    }
    final uploaded = evidence.uploadStatus == UploadStatus.success;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isUploading ? null : _retakePhoto,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('New scan'),
            style: _wideOutlinedButton,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _isUploading || uploaded ? null : _retryUpload,
            icon: _isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(uploaded ? Icons.check : Icons.cloud_upload_outlined),
            label: Text(uploaded ? 'Uploaded' : 'Upload'),
            style: _wideButton,
          ),
        ),
      ],
    );
  }
}

final ButtonStyle _wideButton = FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(52),
);
final ButtonStyle _wideOutlinedButton = OutlinedButton.styleFrom(
  minimumSize: const Size.fromHeight(52),
  foregroundColor: AppColors.ink,
  side: const BorderSide(color: AppColors.line, width: 1.5),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: child,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner.error({required this.message})
    : background = AppColors.dangerSoft,
      foreground = AppColors.danger,
      icon = Icons.error_outline;

  final String message;
  final Color background;
  final Color foreground;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foreground, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureIntro extends StatelessWidget {
  const _CaptureIntro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tips = [
      (Icons.crop_free, 'Get close so the tag fills most of the frame'),
      (Icons.wb_sunny_outlined, 'Use good light and avoid glare on the tag'),
      (Icons.crop_outlined, 'Crop tightly around the tag after taking the photo'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: Color(0xFFF0F0EE),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sell_outlined, size: 40),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Scan an ear tag',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Take a photo of the tag and we will read the number for you.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        for (final tip in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(tip.$1, size: 20, color: AppColors.muted),
                const SizedBox(width: 12),
                Expanded(child: Text(tip.$2)),
              ],
            ),
          ),
      ],
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.photo,
    required this.busy,
    required this.message,
  });

  final Uint8List photo;
  final bool busy;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: AppColors.ink,
            constraints: const BoxConstraints(maxHeight: 460),
            child: Image.memory(photo, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 16),
        if (busy)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Flexible(child: Text(message)),
            ],
          )
        else
          Text(
            'Happy with the photo? Tap Read ear tag.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.evidence});

  final CaptureEvidence evidence;

  String get _tagText {
    final texts = evidence.tagTexts.where((t) => t.trim().isNotEmpty).toList();
    if (texts.isNotEmpty) return texts.first.trim();
    return evidence.ocrText.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagText = _tagText;
    final detection = evidence.tagDetections.isNotEmpty
        ? evidence.tagDetections.first.confidence
        : null;
    final others = evidence.tagTexts.skip(1).where((t) => t.trim().isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'EAR TAG',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.muted,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (tagText.isNotEmpty)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: tagText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                tagText.isEmpty ? 'No text detected' : tagText,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: tagText.isEmpty ? AppColors.muted : AppColors.ink,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (detection != null)
                    _Chip(label: 'Detection ${_percent(detection)}'),
                  if (evidence.tagConfidence != null)
                    _Chip(label: 'OCR ${_percent(evidence.tagConfidence!)}'),
                ],
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Other readings: ${others.join(', ')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _UploadStatusCard(evidence: evidence),
        const SizedBox(height: 16),
        if (evidence.tagCropBytes != null) ...[
          const _SectionLabel('Detected tag'),
          TagCropReview(evidence: evidence, height: 120),
          const SizedBox(height: 16),
        ],
        const _SectionLabel('Photo'),
        OcrImageReview(evidence: evidence),
        const SizedBox(height: 8),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text('Details', style: theme.textTheme.titleSmall),
            children: [
              _DetailLine('Upload', evidence.uploadMessage),
              _DetailLine('Server OCR error', evidence.ocrError),
              _DetailLine('On-device check', evidence.localOcrText),
              _DetailLine('On-device error', evidence.localOcrError),
            ],
          ),
        ),
      ],
    );
  }

  static String _percent(double value) => '${(value * 100).toStringAsFixed(0)}%';
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0EE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
          ),
          SelectableText(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _UploadStatusCard extends StatelessWidget {
  const _UploadStatusCard({required this.evidence});

  final CaptureEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title, Color fg, Color bg) =
        switch (evidence.uploadStatus) {
          UploadStatus.success => (
            Icons.check_circle_outline,
            'Saved to server',
            AppColors.success,
            AppColors.successSoft,
          ),
          UploadStatus.failure => (
            Icons.error_outline,
            'Upload failed - tap Upload to retry',
            AppColors.danger,
            AppColors.dangerSoft,
          ),
          UploadStatus.pending => (
            Icons.cloud_queue,
            'Not uploaded yet',
            AppColors.muted,
            const Color(0xFFF0F0EE),
          ),
        };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
