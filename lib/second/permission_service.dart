// services/permission_service.dart
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class PermissionService {
  /// Check & request permissions untuk video call (Universal)
  static Future<PermissionResult> requestVideoCallPermissions(BuildContext context) async {
    try {
      debugPrint('🔐 Starting video call permission check...');

      if (Platform.isIOS) {
        return await _handleIOSPermissions(context);
      } else {
        return await _handleAndroidPermissions(context);
      }
    } catch (e) {
      debugPrint('❌ Permission service error: $e');
      return PermissionResult.error(e.toString());
    }
  }

  /// Handle iOS Permissions
  static Future<PermissionResult> _handleIOSPermissions(BuildContext context) async {
    debugPrint('📱 iOS Permission Flow');

    // iOS hanya butuh camera & microphone
    final permissions = [Permission.camera, Permission.microphone];
    final Map<Permission, PermissionStatus> statuses = await permissions.request();

    debugPrint('📊 iOS Permission results:');
    statuses.forEach((permission, status) {
      debugPrint('  ${permission.toString().split('.').last}: $status');
    });

    final bool cameraGranted = statuses[Permission.camera]?.isGranted == true;
    final bool microphoneGranted = statuses[Permission.microphone]?.isGranted == true;

    if (cameraGranted && microphoneGranted) {
      debugPrint('✅ All iOS permissions granted');
      await _waitForSystemStability();
      return PermissionResult.allGranted();
    }

    // Check jika permanently denied (iOS tidak ada permanently denied seperti Android)
    // Di iOS, kita langsung arahkan ke settings
    if (!cameraGranted || !microphoneGranted) {
      debugPrint('❌ iOS permissions denied');
      await _showIOSPermissionDialog(context);
      return PermissionResult.essentialDenied();
    }

    return PermissionResult.essentialDenied();
  }

  /// Handle Android Permissions
  static Future<PermissionResult> _handleAndroidPermissions(BuildContext context) async {
    debugPrint('🤖 Android Permission Flow');

    final requiredPermissions = await _getAndroidVideoCallPermissions();
    final Map<Permission, PermissionStatus> statuses = await requiredPermissions.request();

    debugPrint('📊 Android Permission results:');
    statuses.forEach((permission, status) {
      debugPrint('  ${permission.toString().split('.').last}: $status');
    });

    final bool allGranted = _checkAllPermissionsGranted(statuses, requiredPermissions);
    final bool hasEssential = _checkEssentialPermissionsGranted(statuses);
    final List<Permission> permanentlyDenied = _getPermanentlyDeniedPermissions(statuses);

    if (allGranted) {
      debugPrint('✅ All Android permissions granted');
      await _waitForSystemStability();
      return PermissionResult.allGranted();
    }

    if (hasEssential && permanentlyDenied.isEmpty) {
      debugPrint('✅ Essential Android permissions granted');
      await _waitForSystemStability();
      return PermissionResult.essentialGranted();
    }

    if (!hasEssential) {
      debugPrint('❌ Essential Android permissions denied');
      if (permanentlyDenied.isNotEmpty) {
        await _showPermanentlyDeniedDialog(context, permanentlyDenied);
      }
      return PermissionResult.essentialDenied();
    }

    debugPrint('⚠️ Some Android permissions permanently denied');
    await _showPartialDenialDialog(context, permanentlyDenied);
    return PermissionResult.partialGranted(permanentlyDenied);
  }

  /// Dapatkan permission Android berdasarkan versi
  static Future<List<Permission>> _getAndroidVideoCallPermissions() async {
    final List<Permission> permissions = [
      Permission.camera,
      Permission.microphone,
    ];

    final androidVersion = await _getAndroidVersion();
    final majorVersion = int.tryParse(androidVersion.split('.').first) ?? 0;

    // Android 13+ butuh notification permission
    if (majorVersion >= 13) {
      permissions.add(Permission.notification);
    }

    return permissions;
  }

  /// Dialog khusus untuk iOS
  static Future<void> _showIOSPermissionDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Video call requires camera and microphone access. '
              'Please enable them in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openIOSSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Buka pengaturan iOS
  static Future<void> _openIOSSettings() async {
    try {
      // Di iOS, openAppSettings() akan membuka Settings app
      final bool opened = await openAppSettings();
      if (!opened) {
        debugPrint('❌ Failed to open iOS settings');
      }
    } catch (e) {
      debugPrint('❌ Error opening iOS settings: $e');
    }
  }

  /// Dialog untuk Android permanently denied
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
        title: const Text('Permissions Required'),
        content: Text(
          'Video call requires $permissionNames access. '
              'Please enable them in App Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Tunggu system stabil
  static Future<void> _waitForSystemStability() async {
    debugPrint('⏳ Waiting for system stability...');
    if (Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 800));
    } else {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('✅ System stability ensured');
  }

  /// Check jika semua permission granted
  static bool _checkAllPermissionsGranted(
      Map<Permission, PermissionStatus> statuses,
      List<Permission> required
      ) {
    return required.every((permission) =>
    statuses[permission]?.isGranted == true);
  }

  /// Check permission essential
  static bool _checkEssentialPermissionsGranted(Map<Permission, PermissionStatus> statuses) {
    return statuses[Permission.camera]?.isGranted == true &&
        statuses[Permission.microphone]?.isGranted == true;
  }

  /// Dapatkan permanently denied permissions (Android only)
  static List<Permission> _getPermanentlyDeniedPermissions(Map<Permission, PermissionStatus> statuses) {
    return statuses.entries
        .where((entry) => entry.value.isPermanentlyDenied)
        .map((entry) => entry.key)
        .toList();
  }

  /// Dialog untuk partial denial (Android only)
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
        title: const Text('Some Permissions Denied'),
        content: Text(
          '$permissionNames permission was denied. '
              'Video call will work but some features may be limited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Get permission display name
  static String _getPermissionDisplayName(Permission permission) {
    switch (permission) {
      case Permission.camera:
        return 'Camera';
      case Permission.microphone:
        return 'Microphone';
      case Permission.notification:
        return 'Notifications';
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

  /// Simple pre-check
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

/// Result class
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