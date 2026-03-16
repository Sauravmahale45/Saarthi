import 'package:cloud_firestore/cloud_firestore.dart';

class AdminService {

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ===============================
  /// GET ALL TRAVELERS (REALTIME)
  /// ===============================
  Stream<QuerySnapshot> getTravelers() {
    return _firestore
        .collection("users")
        .where("role", isEqualTo: "traveler")
        .snapshots();
  }

  /// ===============================
  /// APPROVE TRAVELER KYC
  /// ===============================
  Future<void> approveTraveler(String uid) async {
    try {
      await _firestore.collection("users").doc(uid).update({
        "kycVerified": true,
        "kycStatus": "approved",
        "kycApprovedAt": FieldValue.serverTimestamp()
      });
    } catch (e) {
      print("Approve Traveler Error: $e");
    }
  }

  /// ===============================
  /// SUSPEND TRAVELER
  /// ===============================
  Future<void> suspendTraveler(String uid) async {
    try {
      await _firestore.collection("users").doc(uid).update({
        "kycVerified": false,
        "kycStatus": "suspended",
        "suspendedAt": FieldValue.serverTimestamp()
      });
    } catch (e) {
      print("Suspend Traveler Error: $e");
    }
  }

  /// ===============================
  /// DELETE USER (ADMIN CONTROL)
  /// ===============================
  Future<void> deleteUser(String uid) async {
    try {
      await _firestore.collection("users").doc(uid).delete();
    } catch (e) {
      print("Delete User Error: $e");
    }
  }

  /// ===============================
  /// GET TRAVELER STATS
  /// ===============================
  Future<Map<String, int>> getTravelerStats() async {
    final snapshot = await _firestore
        .collection("users")
        .where("role", isEqualTo: "traveler")
        .get();

    int active = 0;
    int pending = 0;

    for (var doc in snapshot.docs) {
      final data = doc.data();

      if (data["kycVerified"] == true) {
        active++;
      }

      if (data["kycStatus"] == "submitted") {
        pending++;
      }
    }

    return {
      "active": active,
      "pending": pending,
      "total": snapshot.docs.length
    };
  }
}