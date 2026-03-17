import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'notification_types.dart'; // ← shared constants, no circular dep
import 'fcm_sender.dart'; // ← safe: fcm_sender imports only notification_types

// ─────────────────────────────────────────────────────────────────────────────
//  TOP-LEVEL background handler  (FCM requires a top-level function)
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    '[FCM-BG] type=${message.data['type']}  '
    'title=${message.notification?.title}',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  NotificationService
// ─────────────────────────────────────────────────────────────────────────────
class NotificationService {
  NotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static GoRouter? _router;

  // ══════════════════════════════════════════════════════════════════════════
  //  Setup
  // ══════════════════════════════════════════════════════════════════════════

  static void setRouter(GoRouter router) => _router = router;

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _requestPermissions();
    await _fetchAndStoreFcmToken();
    _messaging.onTokenRefresh.listen(_storeFcmToken);
    _listenForeground();
    await _listenTaps();
  }

  static Future<void> clearFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': FieldValue.delete(),
      });
      debugPrint('[NotificationService] Token cleared for ${user.uid}');
    } catch (e) {
      debugPrint('[NotificationService] clearFcmToken: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Send helpers  (delegate to FcmSender)
  //
  //  Callers can use either:
  //    NotificationService.notifyXxx(...)   ← via this class
  //    FcmSender.notifyXxx(...)             ← directly
  //  Both are exported from notifications.dart.
  // ══════════════════════════════════════════════════════════════════════════

  /// Sender → Traveler: new parcel request.
  static Future<void> notifyParcelRequest({
    required String toUid,
    required String parcelId,
    required String fromCity,
    required String toCity,
    required String category,
    required num price,
    required String senderName,
  }) => FcmSender.notifyParcelRequest(
    toUid: toUid,
    parcelId: parcelId,
    fromCity: fromCity,
    toCity: toCity,
    category: category,
    price: price,
    senderName: senderName,
  );

  /// Traveler → Sender: request accepted.
  static Future<void> notifyParcelAccepted({
    required String toUid,
    required String parcelId,
    required String travelerName,
    required String fromCity,
    required String toCity,
  }) => FcmSender.notifyParcelAccepted(
    toUid: toUid,
    parcelId: parcelId,
    travelerName: travelerName,
    fromCity: fromCity,
    toCity: toCity,
  );

  /// Traveler → Sender: parcel picked up.
  static Future<void> notifyParcelPickedUp({
    required String toUid,
    required String parcelId,
    required String travelerName,
  }) => FcmSender.notifyParcelPickedUp(
    toUid: toUid,
    parcelId: parcelId,
    travelerName: travelerName,
  );

  /// Traveler → Sender: parcel delivered.
  static Future<void> notifyParcelDelivered({
    required String toUid,
    required String parcelId,
    required String travelerName,
  }) => FcmSender.notifyParcelDelivered(
    toUid: toUid,
    parcelId: parcelId,
    travelerName: travelerName,
  );

  /// Traveler → Sender: request rejected or expired.
  static Future<void> notifyParcelRequestRejected({
    required String toUid,
    required String parcelId,
    required String fromCity,
    required String toCity,
  }) => FcmSender.notifyParcelRequestRejected(
    toUid: toUid,
    parcelId: parcelId,
    fromCity: fromCity,
    toCity: toCity,
  );

  /// Admin → Traveler: withdrawal approved.
  static Future<void> notifyWithdrawalApproved({
    required String toUid,
    required num amount,
  }) => FcmSender.notifyWithdrawalApproved(toUid: toUid, amount: amount);

  /// System → any user: generic reminder.
  static Future<void> notifyReminder({
    required String toUid,
    required String parcelId,
    required String fromCity,
    required String toCity,
    String? customTitle,
    String? customBody,
  }) => FcmSender.notifyReminder(
    toUid: toUid,
    parcelId: parcelId,
    fromCity: fromCity,
    toCity: toCity,
    customTitle: customTitle,
    customBody: customBody,
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  Private — permissions / token / listeners / navigation
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> _requestPermissions() async {
    final s = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
    debugPrint('[NotificationService] permission=${s.authorizationStatus}');
  }

  static Future<void> _fetchAndStoreFcmToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) await _storeFcmToken(token);
    } catch (e) {
      debugPrint('[NotificationService] token fetch: $e');
    }
  }

  static Future<void> _storeFcmToken(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
      debugPrint('[NotificationService] Token stored for ${user.uid}');
    } catch (e) {
      debugPrint('[NotificationService] token store: $e');
    }
  }

  static void _listenForeground() {
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint(
        '[NotificationService] foreground: ${msg.notification?.title}',
      );
    });
  }

  static Future<void> _listenTaps() async {
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigate(initial));
    }
    FirebaseMessaging.onMessageOpenedApp.listen(_navigate);
  }

  static void _navigate(RemoteMessage message) {
    if (_router == null) {
      debugPrint('[NotificationService] ⚠️ Router not set.');
      return;
    }

    final type = message.data['type'] as String? ?? '';
    final parcelId = message.data['parcelId'] as String? ?? '';

    debugPrint('[NotificationService] navigate type=$type parcelId=$parcelId');

    switch (type) {
      case NotificationTypes.parcelRequest:
        _router!.go('/traveler');
        break;
      case NotificationTypes.parcelAccepted:
        parcelId.isNotEmpty
            ? _router!.push('/parcel-details/$parcelId')
            : _router!.go('/sender');
        break;
      case NotificationTypes.parcelPickup:
        parcelId.isNotEmpty
            ? _router!.push('/parcel-details/$parcelId')
            : _router!.go('/sender');
        break;
      case NotificationTypes.parcelDelivered:
        parcelId.isNotEmpty
            ? _router!.push('/parcel-details/$parcelId')
            : _router!.go('/sender');
        break;
      case NotificationTypes.parcelRejected:
        parcelId.isNotEmpty
            ? _router!.push('/available-traveler/$parcelId')
            : _router!.go('/sender');
        break;
      case NotificationTypes.withdrawalApproved:
        _router!.go('/traveler');
        break;
      case NotificationTypes.reminder:
        parcelId.isNotEmpty
            ? _router!.push('/traveler-parcel-details/$parcelId')
            : _router!.go('/traveler');
        break;
      default:
        debugPrint('[NotificationService] Unknown type "$type".');
    }
  }
}
