import 'package:flutter/material.dart';

import 'models/capture_evidence.dart';
import 'screens/camera_screen.dart';
import 'screens/home_screen.dart';
import 'screens/photos_screen.dart';
import 'services/capture_repository.dart';
import 'services/upload_service.dart';

class AppColors {
  static const canvas = Color(0xFFF4F5F1);
  static const ink = Color(0xFF202923);
  static const muted = Color(0xFF747C75);
  static const accent = Color(0xFF3D684F);
  static const line = Color(0xFFDCE1DA);
}

class CaptureApp extends StatelessWidget {
  const CaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.canvas,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppColors.accent,
              brightness: Brightness.light,
            ).copyWith(
              primary: AppColors.accent,
              onPrimary: Colors.white,
              surface: AppColors.canvas,
              onSurface: AppColors.ink,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.canvas,
          foregroundColor: AppColors.ink,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: AppColors.canvas,
          indicatorColor: Color(0xFFE2E9E1),
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  List<CaptureEvidence> _captures = [];
  final CaptureRepository _captureRepository = CaptureRepository();
  final UploadService _uploadService = UploadService();

  @override
  void initState() {
    super.initState();
    _loadCaptures();
  }

  Future<void> _loadCaptures() async {
    final captures = await _captureRepository.loadLatest();
    if (mounted) setState(() => _captures = captures);
  }

  Future<void> _keepCapture(CaptureEvidence evidence) async {
    final captures = [..._captures];
    final existingIndex = captures.indexWhere(
      (capture) => capture.id == evidence.id,
    );
    if (existingIndex == -1) {
      captures.insert(0, evidence);
    } else {
      captures[existingIndex] = evidence;
    }
    setState(() => _captures = captures.take(5).toList());
    await _captureRepository.save(evidence);
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (_selectedIndex) {
      1 => CameraScreen(
        onEvidenceChanged: _keepCapture,
        uploadService: _uploadService,
      ),
      2 => PhotosScreen(captures: _captures),
      _ => HomeScreen(
        photoBytes: _captures.isEmpty ? null : _captures.first.imageBytes,
        onOpenCamera: () => setState(() => _selectedIndex = 1),
        onOpenPhotos: () => setState(() => _selectedIndex = 2),
      ),
    };

    return Scaffold(
      body: SafeArea(child: page),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_camera_outlined),
            selectedIcon: Icon(Icons.photo_camera),
            label: 'Camera',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Photos',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _uploadService.close();
    super.dispose();
  }
}
