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

  /// Shows a contextual bottom-sheet style dialog.
  /// Returns true if user tapped the action button.
  static Future<bool> showPermissionDialog(
    BuildContext context, {
    required LocationPermissionStatus status,
  }) async {
    String title;
    String message;
    String actionLabel;
    IconData iconData;

    switch (status) {
      case LocationPermissionStatus.serviceDisabled:
        title = 'GPS is turned off';
        message =
            'Location services are disabled. Enable GPS so Saarthi can '
            'track your delivery in real time.';
        actionLabel = 'Open Settings';
        iconData = Icons.gps_off_rounded;
        break;
      case LocationPermissionStatus.deniedForever:
        title = 'Location access blocked';
        message =
            'Location permission is permanently denied. Open App Settings '
            'and allow "Location" to continue.';
        actionLabel = 'App Settings';
        iconData = Icons.lock_outline_rounded;
        break;
      default:
        title = 'Location required';
        message =
            'Saarthi needs your location to track this delivery in real '
            'time. Tap below to grant permission.';
        actionLabel = 'Grant Permission';
        iconData = Icons.location_on_rounded;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon bubble
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D7DF6).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconData, color: const Color(0xFF2D7DF6), size: 30),
              ),
              const SizedBox(height: 16),

              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF64748B),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 24),

              // Action button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D7DF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Cancel link
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF94A3B8),
                ),
                child: const Text('Not now', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
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
      // Give the user a moment to change the setting, then re-check
      await Future.delayed(const Duration(milliseconds: 500));
      status = await checkStatus();
      return status == LocationPermissionStatus.granted;
    }
    return false;
  }
}
