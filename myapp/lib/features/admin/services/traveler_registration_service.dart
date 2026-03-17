import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRAVELER REGISTRATION SERVICE
//
// Centralises every Firestore write that touches a traveler document so that
// the schema stays consistent across registration, KYC submission, and admin
// review.
//
// Firestore schema (users/{uid}):
//   fullName      : String   ← primary name field (matches KYC form)
//   name          : String   ← alias kept for backward compatibility
//   email         : String
//   dateOfBirth   : String   ← set during KYC submission (e.g. "2000-03-17")
//   address       : String   ← set during KYC submission
//   documentType  : String   ← set during KYC submission (e.g. "Aadhaar Card")
//   photoUrl      : String   (optional profile photo)
//   role          : "traveler"
//   status        : String   ← form-side field: "not_submitted" | "submitted" | "approved" | "rejected"
//   kycStatus     : String   ← admin-side alias (kept in sync)
//   kycVerified   : bool
//   documentUrl   : String   (gov ID photo — set on KYC submission)
//   selfieUrl     : String   (live selfie   — set on KYC submission)
//   submittedAt   : Timestamp (set on KYC submission)
//   kycReviewedAt : Timestamp (set on admin approve / reject)
//   createdAt     : Timestamp (set on registration)
// ─────────────────────────────────────────────────────────────────────────────

class TravelerRegistrationService {
  TravelerRegistrationService._();

  static final _auth = FirebaseAuth.instance;
  static final _db   = FirebaseFirestore.instance;

  // ── 1. Register a new traveler ───────────────────────────────────────────
  //
  // Call after Firebase Auth account creation succeeds.
  // Always seeds role, kycStatus, and kycVerified so queries never miss docs
  // that lack these fields.

  static Future<void> registerTraveler({
    required String uid,
    required String name,
    required String email,
    required String phone,
    required String city,
    String photoUrl = '',
  }) async {
    await _db.collection('users').doc(uid).set({
      // Write both fullName (KYC form field) and name (alias) for compatibility
      'fullName'    : name.trim(),
      'name'        : name.trim(),
      'email'       : email.trim().toLowerCase(),
      'phone'       : phone.trim(),
      'city'        : city.trim(),
      'photoUrl'    : photoUrl.trim(),
      'role'        : 'traveler',          // ← MUST be present for Firestore queries
      'status'      : 'not_submitted',     // ← form-side status field
      'kycStatus'   : 'not_submitted',     // ← admin-side alias (kept in sync)
      'kycVerified' : false,
      'documentUrl' : '',
      'selfieUrl'   : '',
      'dateOfBirth' : '',
      'address'     : '',
      'documentType': '',
      'createdAt'   : FieldValue.serverTimestamp(),
    });
  }

  // ── 2. Traveler submits KYC documents ────────────────────────────────────
  //
  // Call this after uploading both images to Firebase Storage / Cloudinary
  // and obtaining their download URLs.

  static Future<void> submitKyc({
    required String uid,
    required String documentUrl,     // government ID photo URL
    required String selfieUrl,       // live selfie photo URL
    required String dateOfBirth,     // e.g. "2000-03-17"
    required String address,         // e.g. "lasalgaon nashik Maharashtra"
    required String documentType,    // e.g. "Aadhaar Card"
  }) async {
    if (documentUrl.isEmpty || selfieUrl.isEmpty) {
      throw ArgumentError('Both documentUrl and selfieUrl are required.');
    }

    await _db.collection('users').doc(uid).update({
      // Document photos
      'documentUrl'  : documentUrl.trim(),
      'selfieUrl'    : selfieUrl.trim(),
      // Form fields
      'dateOfBirth'  : dateOfBirth.trim(),
      'address'      : address.trim(),
      'documentType' : documentType.trim(),
      // Keep both status aliases in sync so both admin and form queries work
      'status'       : 'submitted',
      'kycStatus'    : 'submitted',
      'kycVerified'  : false,
      'submittedAt'  : FieldValue.serverTimestamp(),
    });
  }

  // ── 3. Admin approves KYC ────────────────────────────────────────────────

  static Future<void> approveKyc(String uid) async {
    await _db.collection('users').doc(uid).update({
      'status'       : 'approved',   // form-side field
      'kycStatus'    : 'approved',   // admin-side alias
      'kycVerified'  : true,
      'kycReviewedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── 4. Admin rejects KYC ─────────────────────────────────────────────────

  static Future<void> rejectKyc(String uid) async {
    await _db.collection('users').doc(uid).update({
      'status'       : 'rejected',   // form-side field
      'kycStatus'    : 'rejected',   // admin-side alias
      'kycVerified'  : false,
      'kycReviewedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── 5. Convenience: current user's uid ───────────────────────────────────

  static String? get currentUid => _auth.currentUser?.uid;
}