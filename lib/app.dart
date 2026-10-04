import 'package:flutter/material.dart';

import 'models/capture_evidence.dart';
import 'screens/camera_screen.dart';
import 'screens/home_screen.dart';
import 'screens/photos_screen.dart';
import 'services/capture_repository.dart';
import 'services/ear_tag_reader.dart';
import 'services/upload_service.dart';

/// Palette derived from the app logo (lib/../assets/icon/app_icon.png):
/// cattle-tag green background, amber ear tag, deep-green shadow accent.
class AppColors {
  static const canvas = Color(0xFFF7F7F5);
  static const panel = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1F1F1F);
  static const muted = Color(0xFF666666);
  static const accent = Color(0xFF12A334); // logo green
  static const accentDark = Color(0xFF025A23); // logo shadow green
  static const tag = Color(0xFFFEBF0D); // logo ear-tag amber
  static const line = Color(0xFFE5E5E1);
  static const success = Color(0xFF2E7D4F);
  static const successSoft = Color(0xFFE6F2EA);
  static const danger = Color(0xFF9E3028);
  static const dangerSoft = Color(0xFFF9E8E6);
}

class CaptureApp extends StatelessWidget {
  const CaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jaguza',
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
              primaryContainer: AppColors.accentDark,
              onPrimaryContainer: Colors.white,
              secondary: AppColors.tag,
              onSecondary: AppColors.ink,
              surface: AppColors.panel,
              onSurface: AppColors.ink,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.canvas,
          foregroundColor: AppColors.ink,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: AppColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.panel,
          indicatorColor: AppColors.accent.withValues(alpha: 0.14),
          elevation: 0,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            return IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? AppColors.accentDark
                  : AppColors.muted,
            );
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.accent,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: AppColors.ink,
          displayColor: AppColors.ink,
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
  final EarTagReader _earTagReader = EarTagReader();
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
        earTagReader: _earTagReader,
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
    _earTagReader.close();
    _uploadService.close();
    super.dispose();
  }
}
