import 'package:flutter/material.dart';

import '../app.dart';
import '../models/capture_evidence.dart';
import '../widgets/ocr_image_review.dart';

class PhotosScreen extends StatelessWidget {
  const PhotosScreen({super.key, required this.captures});

  final List<CaptureEvidence> captures;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photos')),
      body: captures.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 36,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No photos yet',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: captures.length,
              separatorBuilder: (context, index) => const Divider(height: 36),
              itemBuilder: (context, index) {
                final evidence = captures[index];
                final statusColor = switch (evidence.uploadStatus) {
                  UploadStatus.success => AppColors.accent,
                  UploadStatus.failure => const Color(0xFF9E3028),
                  UploadStatus.pending => AppColors.muted,
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OcrImageReview(evidence: evidence),
                    if (evidence.tagCropBytes != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Tag crop',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TagCropReview(evidence: evidence),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      evidence.capturedAt.toLocal().toString().split('.').first,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${evidence.uploadStatus.name.toUpperCase()}: ${evidence.uploadMessage ?? ''}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: statusColor),
                    ),
                    if (evidence.ocrError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'OCR: ${evidence.ocrError}',
                        style: const TextStyle(color: Color(0xFF9E3028)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Detected text',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      evidence.ocrText.isEmpty
                          ? 'No text detected.'
                          : evidence.ocrText,
                    ),
                    if (evidence.tagConfidence != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Tag OCR confidence: ${(evidence.tagConfidence! * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (evidence.blocks.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (
                        var blockIndex = 0;
                        blockIndex < evidence.blocks.length;
                        blockIndex++
                      )
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Block ${blockIndex + 1}: ${evidence.blocks[blockIndex].text} '
                            '(confidence: ${evidence.blocks[blockIndex].confidence?.toStringAsFixed(2) ?? 'not provided'})',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}
