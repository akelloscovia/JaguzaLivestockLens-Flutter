import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.photoBytes,
    required this.onOpenCamera,
    required this.onOpenPhotos,
  });

  final Uint8List? photoBytes;
  final VoidCallback onOpenCamera;
  final VoidCallback onOpenPhotos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jaguza'),
        actions: [
          IconButton(
            onPressed: onOpenPhotos,
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Capture',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ear tag photo',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onOpenCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Open camera'),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenPhotos,
                    child: const Text('View all'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _RecentPhoto(
                  photoBytes: photoBytes,
                  onTap: onOpenPhotos,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentPhoto extends StatelessWidget {
  const _RecentPhoto({required this.photoBytes, required this.onTap});

  final Uint8List? photoBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: photoBytes == null
            ? const Center(
                child: Text(
                  'No photo yet',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : Image.memory(
                photoBytes!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 36,
                    color: AppColors.muted,
                  ),
                ),
              ),
      ),
    );
  }
}
