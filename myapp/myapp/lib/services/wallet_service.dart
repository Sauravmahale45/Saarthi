import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WalletService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get wallet stream for real-time updates
  Stream<DocumentSnapshot> getWalletStream(String userId) {
    return _firestore.collection('wallets').doc(userId).snapshots();
  }

  // Get wallet document reference
  DocumentReference getWalletRef(String userId) {
    return _firestore.collection('wallets').doc(userId);
  }

  // Initialize wallet for new user (optional - can be created on first earning)
  Future<void> initializeWallet(String userId, String userName) async {
    final walletRef = _firestore.collection('wallets').doc(userId);
    final walletDoc = await walletRef.get();

    if (!walletDoc.exists) {
      await walletRef.set({
        'userId': userId,
        'userName': userName,
        'balance': 0.0,
        'pendingWithdrawal': 0.0,
        'totalEarnings': 0.0,
        'totalWithdrawn': 0.0,
        'currency': 'INR',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> addDeliveryEarning({
    required String travelerId,
    required double price,
  }) async {
    final walletRef = _firestore.collection('wallets').doc(travelerId);

    final earning = price * 0.70; // traveler gets 70%

    await walletRef.update({
      'balance': FieldValue.increment(earning),
      'totalEarnings': FieldValue.increment(earning),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Request withdrawal with transaction
  Future<Map<String, dynamic>> requestWithdrawal({
    required String userId,
    required String userName,
    required double amount,
    required String upiId,
  }) async {
    if (amount <= 0) {
      return {'success': false, 'message': 'Amount must be greater than 0'};
    }

    final walletRef = _firestore.collection('wallets').doc(userId);
    final withdrawalRef = _firestore.collection('withdrawals').doc();

    try {
      return await _firestore.runTransaction((transaction) async {
        // Read wallet document within transaction
        final walletSnapshot = await transaction.get(walletRef);

        if (!walletSnapshot.exists) {
          return {'success': false, 'message': 'Wallet not found'};
        }

        final walletData = walletSnapshot.data() as Map<String, dynamic>;
        final currentBalance = (walletData['balance'] ?? 0.0).toDouble();

        // Validate sufficient balance
        if (currentBalance < amount) {
          return {
            'success': false,
            'message':
                'Insufficient balance. Available: ₹${currentBalance.toStringAsFixed(2)}',
          };
        }

        // Update wallet
        transaction.update(walletRef, {
          'balance': FieldValue.increment(-amount),
          'pendingWithdrawal': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Create withdrawal request
        transaction.set(withdrawalRef, {
          'withdrawalId': withdrawalRef.id,
          'travelerId': userId,
          'travelerName': userName,
          'amount': amount,
          'paymentMethod': 'UPI',
          'upiId': upiId,
          'status': 'requested',
          'requestedAt': FieldValue.serverTimestamp(),
          'adminNote': '',
          'processedAt': null,
          'transactionId': null,
        });

        return {
          'success': true,
          'message': 'Withdrawal request submitted successfully',
          'withdrawalId': withdrawalRef.id,
        };
      });
    } catch (e) {
      return {'success': false, 'message': 'Transaction failed: $e'};
    }
  }

  // Get recent withdrawals for a user
  Stream<QuerySnapshot> getUserWithdrawals(String userId) {
    return _firestore
        .collection('withdrawals')
        .where('travelerId', isEqualTo: userId)
        .orderBy('requestedAt', descending: true)
        .limit(20)
        .snapshots();
  }

  // Get recent transactions (parcels delivered)
  Stream<QuerySnapshot> getUserTransactions(String userId) {
    return _firestore
        .collection('parcels')
        .where('travelerId', isEqualTo: userId)
        .where('status', isEqualTo: 'delivered')
        .orderBy('updatedAt', descending: true)
        .limit(20)
        .snapshots();
  }

  // Format currency
  static String formatCurrency(double amount, {String currency = '₹'}) {
    return '$currency ${amount.toStringAsFixed(2)}';
  }
}
