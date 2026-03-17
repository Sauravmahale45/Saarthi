import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/wallet_service.dart';
import '../widgets/withdrawal_form.dart';

class WalletScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const WalletScreen({super.key, required this.userId, required this.userName});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletService _walletService = WalletService();
  late final String _userId;
  late final String _userName;

  @override
  void initState() {
    super.initState();
    _userId = widget.userId;
    _userName = widget.userName;
    _initializeWallet();
  }

  Future<void> _initializeWallet() async {
    await _walletService.initializeWallet(_userId, _userName);
  }

  void _showWithdrawalForm(double availableBalance) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => WithdrawalForm(
        userId: _userId,
        userName: _userName,
        availableBalance: availableBalance,
        onSubmit: (result) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: result['success'] == true
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} min ago';
      }
      return '${difference.inHours} hr ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat('dd MMM yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _walletService.getWalletStream(_userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading wallet: ${snapshot.error}',
                    style: const TextStyle(color: Color(0xFFEF4444)),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildEmptyWallet();
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final balance = (data['balance'] ?? 0.0).toDouble();
          final pendingWithdrawal = (data['pendingWithdrawal'] ?? 0.0)
              .toDouble();
          final totalEarnings = (data['totalEarnings'] ?? 0.0).toDouble();
          final totalWithdrawn = (data['totalWithdrawn'] ?? 0.0).toDouble();
          final currency = data['currency'] ?? 'INR';

          return CustomScrollView(
            slivers: [
              // App Bar
              SliverAppBar(
                expandedHeight: 220,
                floating: false,
                pinned: true,
                backgroundColor: const Color(0xFF4F46E5),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text(
                              'Total Balance',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$currency ${balance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildStatChip(
                                  'Pending',
                                  '$currency ${pendingWithdrawal.toStringAsFixed(2)}',
                                ),
                                const SizedBox(width: 12),
                                _buildStatChip(
                                  'Withdrawn',
                                  '$currency ${totalWithdrawn.toStringAsFixed(2)}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Body content
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Withdraw Button
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 24),
                      child: ElevatedButton.icon(
                        onPressed: balance <= 0
                            ? null
                            : () => _showWithdrawalForm(balance),
                        icon: const Icon(Icons.account_balance_wallet_rounded),
                        label: Text(
                          balance <= 0
                              ? 'Insufficient Balance'
                              : 'Withdraw Money',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(
                            0xFF4F46E5,
                          ).withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),

                    // Stats Cards
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF14B8A6,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.trending_up_rounded,
                                  color: Color(0xFF14B8A6),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Lifetime Summary',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatTile(
                                  'Total Earned',
                                  '$currency ${totalEarnings.toStringAsFixed(2)}',
                                  Icons.account_balance_wallet_rounded,
                                  const Color(0xFF4F46E5),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 50,
                                color: const Color(0xFFE2E8F0),
                              ),
                              Expanded(
                                child: _buildStatTile(
                                  'Net Balance',
                                  '$currency ${balance.toStringAsFixed(2)}',
                                  Icons.account_balance_rounded,
                                  const Color(0xFF14B8A6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Recent Withdrawals Section
                    const Text(
                      'Recent Withdrawals',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildRecentWithdrawals(),

                    const SizedBox(height: 24),

                    // Recent Transactions (from delivered parcels)
                    const Text(
                      'Recent Earnings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildRecentTransactions(),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildEmptyWallet() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                size: 50,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Wallet Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Complete your first delivery to start earning!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentWithdrawals() {
    return StreamBuilder<QuerySnapshot>(
      stream: _walletService.getUserWithdrawals(_userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Icon(Icons.history_rounded, size: 48, color: Color(0xFF94A3B8)),
                SizedBox(height: 12),
                Text(
                  'No withdrawal requests yet',
                  style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                ),
              ],
            ),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final amount = (data['amount'] ?? 0.0).toDouble();
            final status = data['status'] as String? ?? 'requested';
            final upiId = data['upiId'] as String? ?? 'N/A';
            final requestedAt = data['requestedAt'] as Timestamp?;

            Color statusColor;
            IconData statusIcon;
            switch (status) {
              case 'completed':
                statusColor = const Color(0xFF22C55E);
                statusIcon = Icons.check_circle_rounded;
                break;
              case 'rejected':
                statusColor = const Color(0xFFEF4444);
                statusIcon = Icons.cancel_rounded;
                break;
              default:
                statusColor = const Color(0xFFF97316);
                statusIcon = Icons.pending_actions_rounded;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '₹ ${amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          upiId,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTimestamp(requestedAt),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildRecentTransactions() {
    return StreamBuilder<QuerySnapshot>(
      stream: _walletService.getUserTransactions(_userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  size: 48,
                  color: Color(0xFF94A3B8),
                ),
                SizedBox(height: 12),
                Text(
                  'No transactions yet',
                  style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                ),
              ],
            ),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final price = (data['price'] ?? 0.0).toDouble();
            final travelerEarn = price * 0.70; // 70% to traveler
            final fromCity = data['fromCity'] as String? ?? '';
            final toCity = data['toCity'] as String? ?? '';
            final updatedAt = data['updatedAt'] as Timestamp?;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF22C55E),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$fromCity → $toCity',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Earned: ${WalletService.formatCurrency(travelerEarn)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatTimestamp(updatedAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
