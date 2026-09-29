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
      appBar: AppBar(title: const Text('Frame')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        children: [
          Text(
            'Your next\ngood frame.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onOpenCamera,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Open camera'),
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent photo',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: onOpenPhotos,
                child: const Text('View photos'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _RecentPhoto(photoBytes: photoBytes, onTap: onOpenPhotos),
        ],
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 190,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFE9ECE7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: photoBytes == null
            ? const Center(
                child: Icon(
                  Icons.photo_outlined,
                  size: 34,
                  color: AppColors.muted,
                ),
              )
            : Image.memory(
                photoBytes!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              ),
      ),
    );
  }
}
