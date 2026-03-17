import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'notification_types.dart'; // ← only constants, no circular dep

// ─────────────────────────────────────────────────────────────────────────────
//  FcmSender
//
//  One static method per notification type. Each method:
//    1. Accepts only the data it genuinely needs (named, required params).
//    2. Builds a human-readable title + body.
//    3. Calls _sendToUser() which looks up the recipient's FCM token from
//       Firestore and forwards the message to your Cloud Function.
//
//  ── Cloud Function (functions/index.js) ──────────────────────────────────
//  const functions = require('firebase-functions');
//  const admin     = require('firebase-admin');
//  admin.initializeApp();
//
//  exports.sendParcelNotification = functions.https.onCall(
//    async (data, context) => {
//      const { token, title, body, payload } = data;
//      if (!token) throw new functions.https.HttpsError(
//        'invalid-argument', 'token is required');
//      await admin.messaging().send({
//        token,
//        notification: { title, body },
//        data:    payload ?? {},
//        android: { priority: 'high' },
//        apns:    { payload: { aps: { sound: 'default' } } },
//      });
//      return { success: true };
//    }
//  );
// ─────────────────────────────────────────────────────────────────────────────

class FcmSender {
  FcmSender._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Replace with your deployed Cloud Function URL ─────────────────────────
  static const String _cloudFunctionUrl =
      'https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/sendParcelNotification';
  // ──────────────────────────────────────────────────────────────────────────

  // ═══════════════════════════════════════════════════════════════════════════
  //  1.  parcel_request  —  Sender → Traveler
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> notifyParcelRequest({
    required String toUid,
    required String parcelId,
    required String fromCity,
    required String toCity,
    required String category,
    required num price,
    String? senderName,
  }) async {
    await _sendToUser(
      toUid: toUid,
      title: '📦 New Parcel Request!',
      body:
          '${senderName ?? 'A sender'} wants to send a $category '
          'from $fromCity → $toCity for ₹$price. '
          'Tap to review — you have 15 min!',
      data: {
        'type': NotificationTypes.parcelRequest,
        'parcelId': parcelId,
        'fromCity': fromCity,
        'toCity': toCity,
        'category': category,
        'price': price.toString(),
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  2.  parcel_accepted  —  Traveler → Sender
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> notifyParcelAccepted({
    required String toUid,
    required String parcelId,
    required String travelerName,
    required String fromCity,
    required String toCity,
  }) async {
    await _sendToUser(
      toUid: toUid,
      title: '✅ Parcel Request Accepted!',
      body:
          '$travelerName accepted your parcel '
          '($fromCity → $toCity). Please arrange for pickup.',
      data: {'type': NotificationTypes.parcelAccepted, 'parcelId': parcelId},
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  3.  parcel_pickup  —  Traveler → Sender
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> notifyParcelPickedUp({
    required String toUid,
    required String parcelId,
    required String travelerName,
  }) async {
    await _sendToUser(
      toUid: toUid,
      title: '🚌 Parcel Picked Up!',
      body: '$travelerName has collected your parcel and is on the way.',
      data: {'type': NotificationTypes.parcelPickup, 'parcelId': parcelId},
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  4.  parcel_delivered  —  Traveler → Sender
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> notifyParcelDelivered({
    required String toUid,
    required String parcelId,
    required String travelerName,
  }) async {
    await _sendToUser(
      toUid: toUid,
      title: '🎉 Parcel Delivered!',
      body: '$travelerName successfully delivered your parcel.',
      data: {'type': NotificationTypes.parcelDelivered, 'parcelId': parcelId},
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  5.  parcel_rejected  —  Traveler → Sender  (reject + expiry)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> notifyParcelRequestRejected({
    required String toUid,
    required String parcelId,
    required String fromCity,
    required String toCity,
  }) async {
    await _sendToUser(
      toUid: toUid,
      title: '🔄 Looking for Another Traveler',
      body:
          'The traveler couldn\'t take your parcel '
          '($fromCity → $toCity). Tap to choose another traveler.',
      data: {'type': NotificationTypes.parcelRejected, 'parcelId': parcelId},
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  6.  withdrawal_approved  —  Admin → Traveler
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> notifyWithdrawalApproved({
    required String toUid,
    required num amount,
  }) async {
    await _sendToUser(
      toUid: toUid,
      title: '💸 Withdrawal Approved!',
      body:
          '₹$amount has been approved and will be credited to your '
          'bank account shortly.',
      data: {
        'type': NotificationTypes.withdrawalApproved,
        'amount': amount.toString(),
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  7.  reminder  —  System → Traveler or Sender
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> notifyReminder({
    required String toUid,
    required String parcelId,
    required String fromCity,
    required String toCity,
    String? customTitle,
    String? customBody,
  }) async {
    await _sendToUser(
      toUid: toUid,
      title: customTitle ?? '⏰ Reminder: Parcel Delivery',
      body:
          customBody ??
          'Don\'t forget your parcel delivery from '
              '$fromCity → $toCity. Tap for details.',
      data: {
        'type': NotificationTypes.reminder,
        'parcelId': parcelId,
        'fromCity': fromCity,
        'toCity': toCity,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Core plumbing
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _sendToUser({
    required String toUid,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    // Skip self-notifications (edge-case guard).
    final currentUid = _auth.currentUser?.uid;
    if (toUid == currentUid) {
      debugPrint('[FcmSender] Skipping self-notification uid=$toUid');
      return;
    }

    try {
      // 1. Look up recipient FCM token.
      final userDoc = await _db.collection('users').doc(toUid).get();
      if (!userDoc.exists) {
        debugPrint('[FcmSender] No user doc for uid=$toUid — skipping.');
        return;
      }

      final token = userDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) {
        debugPrint('[FcmSender] No FCM token for uid=$toUid — skipping.');
        return;
      }

      // 2. Call Cloud Function.
      await _callCloudFunction(
        token: token,
        title: title,
        body: body,
        payload: data,
      );

      debugPrint('[FcmSender] ✓ type=${data['type']} → uid=$toUid');
    } catch (e) {
      // Never let a notification failure crash the caller.
      debugPrint('[FcmSender] Error → uid=$toUid: $e');
    }
  }

  static Future<void> _callCloudFunction({
    required String token,
    required String title,
    required String body,
    required Map<String, String> payload,
  }) async {
    final response = await http
        .post(
          Uri.parse(_cloudFunctionUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': token,
            'title': title,
            'body': body,
            'payload': payload,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
        'Cloud Function ${response.statusCode}: ${response.body}',
      );
    }
  }
}
