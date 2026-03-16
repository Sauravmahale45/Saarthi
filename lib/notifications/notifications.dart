import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles the background message separately at the top-level (required by FCM).
/// Must be a top-level function, not inside a class.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized when this is called.
  print('[NotificationService] Background message received:');
  print('  Title : ${message.notification?.title}');
  print('  Body  : ${message.notification?.body}');
  print('  Data  : ${message.data}');
}

/// Central service for all Firebase Cloud Messaging (FCM) functionality.
///
/// Usage:
/// ```dart
/// // In main.dart, after Firebase.initializeApp():
/// await NotificationService.initialize();
/// ```
///
/// To send a targeted notification from anywhere in the app, retrieve the
/// recipient's FCM token from Firestore and pass it to your cloud function
/// or backend. This service keeps all notification wiring in one place.
class NotificationService {
  // Private constructor — this is a static-only utility class.
  NotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // ─────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────

  /// Call once from [main.dart] after [Firebase.initializeApp()].
  ///
  /// Performs in order:
  ///   1. Registers the background message handler.
  ///   2. Requests notification permissions from the OS.
  ///   3. Retrieves the device FCM token and saves it to Firestore.
  ///   4. Listens for token refreshes and keeps Firestore in sync.
  ///   5. Subscribes to foreground message events.
  ///   6. Handles the notification that launched the app from terminated state.
  static Future<void> initialize() async {
    // 1. Background handler — must be registered before any other FCM calls.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Request permissions (iOS + Android 13+).
    await _requestPermissions();

    // 3. Retrieve and persist the FCM token.
    await _fetchAndStoreFcmToken();

    // 4. Keep the token fresh — FCM may rotate tokens.
    _messaging.onTokenRefresh.listen((newToken) async {
      print('[NotificationService] Token refreshed: $newToken');
      await _storeFcmToken(newToken);
    });

    // 5. Foreground notifications.
    _listenToForegroundMessages();

    // 6. Handle notification that opened the app from terminated state.
    _handleInitialMessage();
  }

  /// Removes the FCM token from Firestore for the current user.
  /// Call this on sign-out so the user no longer receives push notifications.
  static Future<void> clearFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': FieldValue.delete(),
      });
      print('[NotificationService] FCM token removed for uid: ${user.uid}');
    } catch (e) {
      print('[NotificationService] Failed to remove FCM token: $e');
    }
  }

  // ─────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────

  /// Requests OS-level notification permissions.
  static Future<void> _requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print(
      '[NotificationService] Permission status: ${settings.authorizationStatus}',
    );
  }

  /// Gets the current FCM token and saves it to Firestore.
  static Future<void> _fetchAndStoreFcmToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        print('[NotificationService] FCM token is null — skipping storage.');
        return;
      }
      print('[NotificationService] FCM token: $token');
      await _storeFcmToken(token);
    } catch (e) {
      print('[NotificationService] Error fetching FCM token: $e');
    }
  }

  /// Persists [token] under the authenticated user's Firestore document.
  ///
  /// Document path: `users/{uid}`
  /// Field written : `fcmToken`
  static Future<void> _storeFcmToken(String token) async {
    final user = _auth.currentUser;
    if (user == null) {
      print(
        '[NotificationService] No authenticated user — cannot store FCM token.',
      );
      return;
    }

    try {
      await _firestore.collection('users').doc(user.uid).set(
        {'fcmToken': token},
        SetOptions(merge: true), // Don't overwrite other user fields.
      );
      print(
        '[NotificationService] FCM token saved to Firestore for uid: ${user.uid}',
      );
    } catch (e) {
      print('[NotificationService] Failed to store FCM token: $e');
    }
  }

  /// Subscribes to [FirebaseMessaging.onMessage] — fires while the app is open.
  static void _listenToForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('[NotificationService] Foreground message received:');
      print('  Title : ${message.notification?.title}');
      print('  Body  : ${message.notification?.body}');
      print('  Data  : ${message.data}');

      // Delegate to the appropriate feature handler based on the data payload.
      _routeNotification(message);
    });
  }

  /// Checks whether the app was opened via a notification tap (terminated state).
  static Future<void> _handleInitialMessage() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      print('[NotificationService] App launched via notification:');
      print('  Title : ${initialMessage.notification?.title}');
      print('  Body  : ${initialMessage.notification?.body}');
      _routeNotification(initialMessage);
    }

    // Also handle notification taps when the app is in the background
    // (not terminated) — this stream emits when the user taps the banner.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print(
        '[NotificationService] Notification tapped (background → foreground):',
      );
      print('  Title : ${message.notification?.title}');
      print('  Body  : ${message.notification?.body}');
      _routeNotification(message);
    });
  }

  // ─────────────────────────────────────────────
  // Notification routing
  // ─────────────────────────────────────────────

  /// Routes an incoming notification to the correct feature handler based on
  /// the `type` field inside [message.data].
  ///
  /// Add a new `case` here when you introduce a new notification type for
  /// features like parcel requests, acceptance, pickup, delivery, withdrawals,
  /// or reminders — keeping all routing logic in one place.
  ///
  /// Expected data payload shape:
  /// ```json
  /// {
  ///   "type": "parcel_request",   // or any type listed below
  ///   "parcelId": "abc123",       // optional, feature-specific fields
  ///   ...
  /// }
  /// ```
  static void _routeNotification(RemoteMessage message) {
    final type = message.data['type'] as String?;

    switch (type) {
      case NotificationTypes.parcelRequest:
        print('[NotificationService] → Routing to: Parcel Request handler');
        // TODO: Navigate to parcel request screen or trigger relevant state.
        break;

      case NotificationTypes.parcelAccepted:
        print('[NotificationService] → Routing to: Parcel Accepted handler');
        // TODO: Navigate to parcel tracking / confirmation screen.
        break;

      case NotificationTypes.parcelPickup:
        print('[NotificationService] → Routing to: Parcel Pickup handler');
        // TODO: Trigger pickup confirmation flow.
        break;

      case NotificationTypes.parcelDelivered:
        print('[NotificationService] → Routing to: Parcel Delivered handler');
        // TODO: Show delivery confirmation and rating prompt.
        break;

      case NotificationTypes.withdrawalApproved:
        print(
          '[NotificationService] → Routing to: Withdrawal Approved handler',
        );
        // TODO: Navigate to wallet / transaction screen.
        break;

      case NotificationTypes.reminder:
        print('[NotificationService] → Routing to: Reminder handler');
        // TODO: Show reminder dialog or navigate to relevant screen.
        break;

      default:
        print(
          '[NotificationService] Unknown notification type: "$type". No routing applied.',
        );
    }
  }
}

// ─────────────────────────────────────────────
// Notification type constants
// ─────────────────────────────────────────────

/// String constants for notification `type` values.
///
/// Use these same strings as the `type` value in your FCM data payloads
/// (sent from Cloud Functions or your backend) so routing stays consistent.
///
/// Example FCM payload:
/// ```json
/// {
///   "to": "<fcm_token>",
///   "notification": { "title": "New Request", "body": "Someone needs a delivery." },
///   "data": { "type": "parcel_request", "parcelId": "xyz" }
/// }
/// ```
class NotificationTypes {
  NotificationTypes._();

  static const String parcelRequest = 'parcel_request';
  static const String parcelAccepted = 'parcel_accepted';
  static const String parcelPickup = 'parcel_pickup';
  static const String parcelDelivered = 'parcel_delivered';
  static const String withdrawalApproved = 'withdrawal_approved';
  static const String reminder = 'reminder';
}
