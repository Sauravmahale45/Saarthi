// lib/features/tracking/permission_service.dart
//
// Handles all location permission and GPS service checks.
// Used before starting pickup OTP flow and before activating tracking.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

class PermissionService {
  /// Checks current permission state without requesting.
  static Future<LocationPermissionStatus> checkStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationPermissionStatus.serviceDisabled;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      return LocationPermissionStatus.denied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionStatus.deniedForever;
    }
    return LocationPermissionStatus.granted;
  }

  /// Requests permission if needed. Returns final status.
  static Future<LocationPermissionStatus> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationPermissionStatus.serviceDisabled;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return LocationPermissionStatus.denied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionStatus.deniedForever;
    }
    return LocationPermissionStatus.granted;
  }

  /// Shows a contextual dialog. Returns true if user tapped the action button.
  static Future<bool> showPermissionDialog(
    BuildContext context, {
    required LocationPermissionStatus status,
  }) async {
    String title;
    String message;
    String actionLabel;

    switch (status) {
      case LocationPermissionStatus.serviceDisabled:
        title = 'GPS Disabled';
        message =
            'Location services are turned off. Please enable GPS to '
            'start tracking your delivery.';
        actionLabel = 'Open Settings';
        break;
      case LocationPermissionStatus.deniedForever:
        title = 'Location Permission Blocked';
        message =
            'Location permission has been permanently denied. Please go '
            'to App Settings and allow location access to continue.';
        actionLabel = 'App Settings';
        break;
      default:
        title = 'Location Required';
        message =
            'Saarthi needs location access to track your delivery in '
            'real time. Please grant location permission.';
        actionLabel = 'Grant Permission';
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (result == true) {
      if (status == LocationPermissionStatus.serviceDisabled) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
      return true;
    }
    return false;
  }

  /// Full flow: check → request → show dialog if needed.
  /// Returns true only if permission is fully granted and GPS is on.
  static Future<bool> ensureLocationReady(BuildContext context) async {
    var status = await requestPermission();
    if (status == LocationPermissionStatus.granted) return true;

    if (!context.mounted) return false;

    final opened = await showPermissionDialog(context, status: status);
    if (opened) {
      status = await checkStatus();
      return status == LocationPermissionStatus.granted;
    }
    return false;
  }
}
