import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class TrackingService {
  TrackingService._();

  static TrackingService? _instance;
  static TrackingService get instance => _instance ??= TrackingService._();

  // ── State ──────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _positionSub;
  String? _activeParcelId;
  bool _isTracking = false;

  bool get isTracking => _isTracking;
  String? get activeParcelId => _activeParcelId;

  // ── Firestore reference ────────────────────────────────────────────────────
  DocumentReference _locationDoc(String parcelId) =>
      FirebaseFirestore.instance.collection('locations').doc(parcelId);

  // ── Start tracking ─────────────────────────────────────────────────────────
  /// Call this after pickup OTP is verified and parcel status = 'picked'.
  /// [parcelId] identifies which locations/{parcelId} document to update.
  Future<void> startTracking(String parcelId) async {
    if (_isTracking && _activeParcelId == parcelId) {
      debugPrint('TrackingService: already tracking $parcelId');
      return;
    }

    // Stop any existing session first
    await stopTracking();

    _activeParcelId = parcelId;
    _isTracking = true;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20, // metres – balances accuracy vs battery
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          (Position pos) => _onPosition(parcelId, pos),
          onError: (Object err) {
            debugPrint('TrackingService: position stream error – $err');
          },
          cancelOnError: false,
        );

    debugPrint('TrackingService: started for parcel $parcelId');
  }

  // ── Handle each position fix ───────────────────────────────────────────────
  Future<void> _onPosition(String parcelId, Position pos) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    try {
      await _locationDoc(parcelId).set({
        'travelerId': uid,
        'parcelId': parcelId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'speed': pos.speed, // m/s
        'accuracy': pos.accuracy, // metres
        'heading': pos.heading, // degrees (0–360) – used for marker rotation
        'updatedAt': FieldValue.serverTimestamp(),
      }); // set() overwrites the single document – no growth
    } catch (e) {
      debugPrint('TrackingService: Firestore write failed – $e');
    }
  }

  // ── Stop tracking ──────────────────────────────────────────────────────────
  Future<void> stopTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _isTracking = false;

    if (_activeParcelId != null) {
      debugPrint('TrackingService: stopped for parcel $_activeParcelId');
    }
    _activeParcelId = null;
  }

  // ── Dispose (call from app shutdown or logout) ─────────────────────────────
  Future<void> dispose() async {
    await stopTracking();
    _instance = null;
  }
}
