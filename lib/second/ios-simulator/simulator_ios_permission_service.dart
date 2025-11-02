// services/dev_permission_service.dart
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class SimulatorIosPermissionService {
  /// Bypass permission checks untuk development
  static Future<bool> requestVideoCallPermissions(BuildContext context) async {
    const bool isDevelopment = true; // Set ke false untuk production

    if (isDevelopment) {
      debugPrint('🛠️ DEVELOPMENT MODE - Bypassing permission checks');

      if (Platform.isIOS) {
        final deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        if (!iosInfo.isPhysicalDevice) {
          debugPrint('🎮 iOS Simulator - Auto granting permissions');
          return true;
        }
      }

      // Untuk development di real device, tetap request permission
      final statuses = await [Permission.camera, Permission.microphone].request();
      return statuses[Permission.camera]?.isGranted == true ||
          statuses[Permission.microphone]?.isGranted == true;
    }
    else {
      // Production mode - strict permission checks
      final statuses = await [Permission.camera, Permission.microphone].request();
      return statuses[Permission.camera]?.isGranted == true &&
          statuses[Permission.microphone]?.isGranted == true;
    }
  }
}