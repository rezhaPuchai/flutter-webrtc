// services/permission_service.dart
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class PermissionService {
  static final Map<Permission, PermissionStatus> _permissionCache = {};

  /// Check & request semua permission yang dibutuhkan untuk video call
  static Future<PermissionResult> requestVideoCallPermissions(BuildContext context) async {
    try {
      print('🔐 Starting video call permission check...');

      // Clear cache untuk memastikan data terbaru
      _permissionCache.clear();

      // Dapatkan permission yang diperlukan berdasarkan platform dan versi
      final requiredPermissions = await _getRequiredVideoCallPermissions();

      print('📋 Required permissions: ${requiredPermissions.map((p) => p.toString().split('.').last)}');

      // Request permissions
      final Map<Permission, PermissionStatus> statuses =
      await requiredPermissions.request();

      // Cache results
      _permissionCache.addAll(statuses);

      // Check hasil
      final bool allGranted = _checkAllPermissionsGranted(statuses, requiredPermissions);
      final bool hasEssential = _checkEssentialPermissionsGranted(statuses);
      final List<Permission> permanentlyDenied = _getPermanentlyDeniedPermissions(statuses);

      print('📊 Permission results:');
      statuses.forEach((permission, status) {
        print('  ${permission.toString().split('.').last}: $status');
      });

      if (allGranted) {
        print('✅ All permissions granted');
        // Tunggu sebentar untuk memastikan system ready
        await _waitForSystemStability();
        return PermissionResult.allGranted();
      }

      if (hasEssential && permanentlyDenied.isEmpty) {
        print('✅ Essential permissions granted (some optional denied)');
        await _waitForSystemStability();
        return PermissionResult.essentialGranted();
      }

      if (!hasEssential) {
        print('❌ Essential permissions denied');
        if (permanentlyDenied.isNotEmpty) {
          await _showPermanentlyDeniedDialog(context, permanentlyDenied);
        }
        return PermissionResult.essentialDenied();
      }

      // Partial grants dengan permanent denied
      print('⚠️ Some permissions permanently denied');
      await _showPartialDenialDialog(context, permanentlyDenied);
      return PermissionResult.partialGranted(permanentlyDenied);

    } catch (e) {
      print('❌ Permission service error: $e');
      return PermissionResult.error(e.toString());
    }
  }

  /// Dapatkan permission yang diperlukan berdasarkan platform dan versi
  static Future<List<Permission>> _getRequiredVideoCallPermissions() async {
    final List<Permission> permissions = [
      Permission.camera,
      Permission.microphone,
    ];

    if (Platform.isAndroid) {
      final androidVersion = await _getAndroidVersion();
      final majorVersion = int.tryParse(androidVersion.split('.').first) ?? 0;

      // Android 13+ (API 33+) butuh notification permission
      if (majorVersion >= 13) {
        permissions.add(Permission.notification);
      }

      // Android 10+ butuh background audio untuk call continuity
      if (majorVersion >= 10) {
        permissions.add(Permission.accessNotificationPolicy);
      }
    }

    if (Platform.isIOS) {
      permissions.addAll([
        Permission.speech, // Untuk voice activation
        Permission.appTrackingTransparency, // Untuk analytics (opsional)
      ]);
    }

    return permissions;
  }

  /// Check jika semua permission granted
  static bool _checkAllPermissionsGranted(
      Map<Permission, PermissionStatus> statuses,
      List<Permission> required
      ) {
    return required.every((permission) =>
    statuses[permission]?.isGranted == true);
  }

  /// Check jika permission essential (camera & mic) granted
  static bool _checkEssentialPermissionsGranted(Map<Permission, PermissionStatus> statuses) {
    return statuses[Permission.camera]?.isGranted == true &&
        statuses[Permission.microphone]?.isGranted == true;
  }

  /// Dapatkan permission yang permanently denied
  static List<Permission> _getPermanentlyDeniedPermissions(Map<Permission, PermissionStatus> statuses) {
    return statuses.entries
        .where((entry) => entry.value.isPermanentlyDenied)
        .map((entry) => entry.key)
        .toList();
  }

  /// Tunggu system stabil setelah permission granted
  static Future<void> _waitForSystemStability() async {
    print('⏳ Waiting for system stability...');
    // Delay bertahap berdasarkan platform
    if (Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 800));
    } else {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    print('✅ System stability ensured');
  }

  /// Dialog untuk permanently denied permissions
  static Future<void> _showPermanentlyDeniedDialog(
      BuildContext context,
      List<Permission> deniedPermissions
      ) async {
    final permissionNames = deniedPermissions
        .map((p) => _getPermissionDisplayName(p))
        .join(', ');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Izin Diperlukan'),
        content: Text(
          'Aplikasi membutuhkan akses $permissionNames untuk video call. '
              'Silakan berikan izin melalui pengaturan aplikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Nanti'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Buka Pengaturan'),
          ),
        ],
      ),
    );
  }

  /// Dialog untuk partial denial
  static Future<void> _showPartialDenialDialog(
      BuildContext context,
      List<Permission> deniedPermissions
      ) async {
    final permissionNames = deniedPermissions
        .map((p) => _getPermissionDisplayName(p))
        .join(', ');

    await showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Beberapa Izin Ditolak'),
        content: Text(
          'Izin $permissionNames ditolak. Fitur video call tetap dapat digunakan '
              'tetapi beberapa fungsi mungkin terbatas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  /// Get user-friendly permission names
  static String _getPermissionDisplayName(Permission permission) {
    switch (permission) {
      case Permission.camera:
        return 'Kamera';
      case Permission.microphone:
        return 'Mikrofon';
      case Permission.notification:
        return 'Notifikasi';
      case Permission.speech:
        return 'Pengenalan Suara';
      default:
        return permission.toString().split('.').last;
    }
  }

  /// Get Android version
  static Future<String> _getAndroidVersion() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.version.release;
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /// Pre-check permissions sebelum navigasi (optional)
  static Future<bool> checkEssentialPermissionsPreflight() async {
    try {
      final cameraStatus = await Permission.camera.status;
      final microphoneStatus = await Permission.microphone.status;

      return cameraStatus.isGranted && microphoneStatus.isGranted;
    } catch (e) {
      return false;
    }
  }
}

/// Result class untuk permission handling
class PermissionResult {
  final bool success;
  final bool allGranted;
  final bool essentialGranted;
  final List<Permission>? deniedPermissions;
  final String? error;

  PermissionResult({
    required this.success,
    required this.allGranted,
    required this.essentialGranted,
    this.deniedPermissions,
    this.error,
  });

  factory PermissionResult.allGranted() {
    return PermissionResult(
      success: true,
      allGranted: true,
      essentialGranted: true,
    );
  }

  factory PermissionResult.essentialGranted() {
    return PermissionResult(
      success: true,
      allGranted: false,
      essentialGranted: true,
    );
  }

  factory PermissionResult.essentialDenied() {
    return PermissionResult(
      success: false,
      allGranted: false,
      essentialGranted: false,
    );
  }

  factory PermissionResult.partialGranted(List<Permission> deniedPermissions) {
    return PermissionResult(
      success: true,
      allGranted: false,
      essentialGranted: true,
      deniedPermissions: deniedPermissions,
    );
  }

  factory PermissionResult.error(String error) {
    return PermissionResult(
      success: false,
      allGranted: false,
      essentialGranted: false,
      error: error,
    );
  }
}