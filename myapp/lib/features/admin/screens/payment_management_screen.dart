import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentManagementScreen extends StatefulWidget {
  const PaymentManagementScreen({Key? key}) : super(key: key);

  @override
  State<PaymentManagementScreen> createState() =>
      _PaymentManagementScreenState();
}

class _PaymentManagementScreenState extends State<PaymentManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Design tokens ──────────────────────────────
  static const Color _bg = Color(0xFFF4F6FA);
  static const Color _surface = Colors.white;
  static const Color _primary = Color(0xFF1A56DB);
  static const Color _green = Color(0xFF0E9F6E);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _orange = Color(0xFFF59E0B);
  static const Color _purple = Color(0xFF8B5CF6);
  static const Color _greenBg = Color(0xFFECFDF5);
  static const Color _blueBg = Color(0xFFEFF6FF);
  static const Color _orangeBg = Color(0xFFFFFBEB);
  static const Color _purpleBg = Color(0xFFF5F3FF);
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const double _radius = 16;

  // ── Withdrawal status values in YOUR Firestore ─
  // status: "requested" | "approved" | "rejected"

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────

  String _fmt(double v) =>
      '₹${v.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    return ts.toString();
  }

  // ── Status helpers — maps YOUR status strings ──

  /// Normalize: "requested" → "pending" display logic
  String _normalizeStatus(String s) => s.toLowerCase();

  Color _statusColor(String s) {
    switch (_normalizeStatus(s)) {
      case 'paid':
      case 'approved':
        return _green;
      case 'pending':
      case 'requested':
        return _orange;
      case 'failed':
      case 'rejected':
        return Colors.red;
      default:
        return _textSecondary;
    }
  }

  Color _statusBg(String s) {
    switch (_normalizeStatus(s)) {
      case 'paid':
      case 'approved':
        return _greenBg;
      case 'pending':
      case 'requested':
        return _orangeBg;
      case 'failed':
      case 'rejected':
        return const Color(0xFFFEF2F2);
      default:
        return _bg;
    }
  }

  IconData _statusIcon(String s) {
    switch (_normalizeStatus(s)) {
      case 'paid':
      case 'approved':
        return Icons.check_circle_rounded;
      case 'pending':
      case 'requested':
        return Icons.hourglass_top_rounded;
      case 'failed':
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  String _statusLabel(String s) {
    switch (_normalizeStatus(s)) {
      case 'requested':
        return 'Requested';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'paid':
        return 'Paid';
      case 'pending':
        return 'Pending';
      case 'failed':
        return 'Failed';
      default:
        if (s.isEmpty) return 'Unknown';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  bool _isActionable(String s) =>
      _normalizeStatus(s) == 'requested' || _normalizeStatus(s) == 'pending';

  // ── Financial Summary stream ────────────────────
  // parcels  → revenue (paymentStatus == "paid") + travelerEarning
  // withdrawals → pending (status == "requested") + withdrawn (status == "approved")

  Stream<Map<String, double>> get _summaryStream {
    return _db.collection('parcels').snapshots().asyncMap((parcelSnap) async {
      double revenue = 0, earnings = 0;
      for (final doc in parcelSnap.docs) {
        final d = doc.data();
        if ((d['paymentStatus'] ?? '').toString().toLowerCase() == 'paid') {
          revenue += _toDouble(d['price']);
        }
        earnings += _toDouble(d['travelerEarning'] ?? d['travelerAmount'] ?? 0);
      }

      final wSnap = await _db.collection('withdrawals').get();
      double pending = 0, withdrawn = 0;
      for (final doc in wSnap.docs) {
        final d = doc.data();
        final st = (d['status'] ?? '').toString().toLowerCase();
        final amt = _toDouble(d['amount']); // ← your field name
        if (st == 'requested' || st == 'pending') pending += amt;
        if (st == 'approved') withdrawn += amt;
      }

      return {
        'revenue': revenue,
        'earnings': earnings,
        'pending': pending,
        'withdrawn': withdrawn,
      };
    });
  }

  // ── Withdrawal approve / reject ─────────────────
  // Fields written: status, processedAt, adminNote
  // On approve: also updates wallets/{travelerId}

  Future<void> _updateWithdrawal({
    required String docId,
    required String withdrawalId,
    required String newStatus,
    required double amount,
    required String travelerId,
    String adminNote = '',
  }) async {
    final batch = _db.batch();

    batch.update(_db.collection('withdrawals').doc(docId), {
      'status': newStatus, // "approved" | "rejected"
      'processedAt': FieldValue.serverTimestamp(),
      if (adminNote.isNotEmpty) 'adminNote': adminNote,
    });

    if (newStatus == 'approved') {
      final walletRef = _db.collection('wallets').doc(travelerId);
      batch.update(walletRef, {
        'balance': FieldValue.increment(-amount),
        'totalWithdrawn': FieldValue.increment(amount),
      });
    }

    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newStatus == 'approved'
              ? '✓ Withdrawal approved — ₹${amount.toStringAsFixed(0)} released'
              : '✗ Withdrawal request rejected',
        ),
        backgroundColor: newStatus == 'approved' ? _green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── BUILD ───────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Summary cards
          StreamBuilder<Map<String, double>>(
            stream: _summaryStream,
            builder: (ctx, snap) {
              final data =
                  snap.data ??
                  {'revenue': 0, 'earnings': 0, 'pending': 0, 'withdrawn': 0};
              return _buildSummaryRow(data);
            },
          ),
          // Tab bar
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(4),
              labelColor: Colors.white,
              unselectedLabelColor: _textSecondary,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
              tabs: const [
                Tab(text: 'Sender Payments'),
                Tab(text: 'Withdrawal Requests'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildPaymentsTab(), _buildWithdrawalsTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      elevation: 0,
      shadowColor: Colors.black12,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.payments_rounded, color: _primary, size: 20),
        ),
      ),
      leadingWidth: 56,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment Management',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          Text(
            'Admin Dashboard',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CircleAvatar(
            radius: 17,
            backgroundColor: _primary.withOpacity(0.12),
            child: const Icon(Icons.person_rounded, color: _primary, size: 18),
          ),
        ),
      ],
    );
  }

  // ── Summary Cards ───────────────────────────────

  Widget _buildSummaryRow(Map<String, double> data) {
    final cards = [
      _SummaryCard(
        label: 'Total Revenue',
        amount: _fmt(data['revenue']!),
        icon: Icons.trending_up_rounded,
        color: _green,
        bg: _greenBg,
        sub: 'Sender payments received',
      ),

      _SummaryCard(
        label: 'Pending Withdrawals',
        amount: _fmt(data['pending']!),
        icon: Icons.hourglass_top_rounded,
        color: _orange,
        bg: _orangeBg,
        sub: 'Awaiting approval',
      ),
      _SummaryCard(
        label: 'Total Withdrawn',
        amount: _fmt(data['withdrawn']!),
        icon: Icons.done_all_rounded,
        color: _purple,
        bg: _purpleBg,
        sub: 'Already paid out',
      ),
    ];

    return SizedBox(
      height: 130,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _summaryCardWidget(cards[i]),
      ),
    );
  }

  Widget _summaryCardWidget(_SummaryCard c) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: c.color.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(c.icon, color: c.color, size: 18),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  c.label,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.amount,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                c.sub,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Payments Tab ────────────────────────────────

  Widget _buildPaymentsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('parcels')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) return _errorWidget(snap.error.toString());
        if (snap.connectionState == ConnectionState.waiting) {
          return _loadingWidget();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return _emptyWidget('No payment transactions found');
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            return _buildPaymentCard(d, docs[i].id);
          },
        );
      },
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> d, String docId) {
    final status = (d['paymentStatus'] ?? 'pending').toString();
    final amount = _toDouble(d['price']);

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: _bg.withOpacity(0.6),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(_radius),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: _blue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${(d['orderId'] ?? docId).toString().toUpperCase()}',
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Payment ID: ${d['paymentId'] ?? '—'}',
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(status),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _infoRow(
                        Icons.person_outline_rounded,
                        'Sender',
                        d['senderName'] ?? '—',
                      ),
                      const SizedBox(height: 7),
                      _infoRow(
                        Icons.location_on_outlined,
                        'Receiver',
                        d['receiverName'] ?? '—',
                      ),
                      const SizedBox(height: 7),
                      _infoRow(
                        Icons.phone_outlined,
                        'Receiver Ph.',
                        d['receiverPhone'] ?? '—',
                      ),
                      const SizedBox(height: 7),
                      _infoRow(
                        Icons.delivery_dining_rounded,
                        'Traveler',
                        d['travelerName'] ?? '—',
                      ),
                      const SizedBox(height: 7),
                      _infoRow(
                        Icons.calendar_today_outlined,
                        'Date',
                        _formatTs(d['createdAt']),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmt(amount),
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Amount',
                      style: TextStyle(color: _textSecondary, fontSize: 10.5),
                    ),
                    const SizedBox(height: 16),
                    _outlinedButton(
                      label: 'View Details',
                      icon: Icons.open_in_new_rounded,
                      color: _primary,
                      onTap: () => _showPaymentDetails(context, d, docId),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Withdrawals Tab ─────────────────────────────
  // Reads YOUR exact field names:
  //   withdrawalId, travelerId, travelerName, amount, upiId,
  //   paymentMethod, status, requestedAt, processedAt,
  //   transactionId, adminNote

  Widget _buildWithdrawalsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('withdrawals')
          .orderBy('requestedAt', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) return _errorWidget(snap.error.toString());
        if (snap.connectionState == ConnectionState.waiting) {
          return _loadingWidget();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return _emptyWidget('No withdrawal requests found');
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            return _buildWithdrawalCard(d, docs[i].id);
          },
        );
      },
    );
  }

  Widget _buildWithdrawalCard(Map<String, dynamic> d, String docId) {
    // ── YOUR exact field names ──
    final status = (d['status'] ?? 'requested').toString();
    final amount = _toDouble(d['amount']); // number
    final travelerId = (d['travelerId'] ?? '').toString();
    final travelerName = (d['travelerName'] ?? 'Traveler').toString();
    final upiId = (d['upiId'] ?? '—').toString();
    final paymentMethod = (d['paymentMethod'] ?? '—').toString();
    final requestedAt = d['requestedAt'];
    final processedAt = d['processedAt'];
    final transactionId = d['transactionId'];
    final adminNote = (d['adminNote'] ?? '').toString();
    final withdrawalId = (d['withdrawalId'] ?? docId).toString();
    final actionable = _isActionable(status);

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(_radius),
        border: actionable
            ? Border.all(color: _orange.withOpacity(0.35), width: 1.3)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row ──
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _purple.withOpacity(0.12),
                  child: Text(
                    travelerName.isNotEmpty
                        ? travelerName[0].toUpperCase()
                        : 'T',
                    style: const TextStyle(
                      color: _purple,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        travelerName,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'ID: ${travelerId.length > 14 ? '${travelerId.substring(0, 14)}...' : travelerId}',
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(status),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
            const SizedBox(height: 14),

            // ── Amount + method + UPI ──
            Row(
              children: [
                Expanded(child: _statBlock('Requested', _fmt(amount), _orange)),
                _dividerV(),
                Expanded(child: _statBlock('Method', paymentMethod, _blue)),
                _dividerV(),
                Expanded(
                  child: _statBlock(
                    'UPI ID',
                    upiId,
                    _textSecondary,
                    small: true,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Dates row ──
            Row(
              children: [
                Expanded(
                  child: _infoRow(
                    Icons.schedule_rounded,
                    'Requested',
                    _formatTs(requestedAt),
                  ),
                ),
              ],
            ),
            if (processedAt != null) ...[
              const SizedBox(height: 6),
              _infoRow(
                Icons.check_circle_outline_rounded,
                'Processed',
                _formatTs(processedAt),
              ),
            ],
            if (transactionId != null &&
                transactionId.toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              _infoRow(Icons.tag_rounded, 'Txn ID', transactionId.toString()),
            ],
            if (adminNote.isNotEmpty) ...[
              const SizedBox(height: 6),
              _infoRow(Icons.note_alt_outlined, 'Note', adminNote),
            ],

            // ── Withdrawal ID ──
            const SizedBox(height: 6),
            _infoRow(
              Icons.fingerprint_rounded,
              'Withdrawal ID',
              withdrawalId.length > 16
                  ? '${withdrawalId.substring(0, 16)}...'
                  : withdrawalId,
            ),

            // ── Action buttons (only for "requested" status) ──
            if (actionable) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _approveButton(
                      onTap: () => _confirmAction(
                        context: context,
                        title: 'Approve Withdrawal',
                        message:
                            'Approve ${_fmt(amount)} for $travelerName via $paymentMethod ($upiId)?',
                        confirmLabel: 'Approve',
                        confirmColor: _green,
                        onConfirm: () => _updateWithdrawal(
                          docId: docId,
                          withdrawalId: withdrawalId,
                          newStatus: 'approved',
                          amount: amount,
                          travelerId: travelerId,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _rejectButton(
                      onTap: () => _confirmAction(
                        context: context,
                        title: 'Reject Request',
                        message:
                            'Reject ${_fmt(amount)} withdrawal for $travelerName?',
                        confirmLabel: 'Reject',
                        confirmColor: Colors.red,
                        onConfirm: () => _updateWithdrawal(
                          docId: docId,
                          withdrawalId: withdrawalId,
                          newStatus: 'rejected',
                          amount: amount,
                          travelerId: travelerId,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Reusable widgets ────────────────────────────

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _statusBg(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), color: _statusColor(status), size: 12),
          const SizedBox(width: 4),
          Text(
            _statusLabel(status),
            style: TextStyle(
              color: _statusColor(status),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _textSecondary),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w400,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _outlinedButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _approveButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0E9F6E), Color(0xFF057A55)],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: _green.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_rounded, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text(
              'Approve Withdrawal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rejectButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.close_rounded, color: Colors.red, size: 16),
            SizedBox(width: 6),
            Text(
              'Reject Request',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBlock(
    String label,
    String value,
    Color color, {
    bool small = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: small ? 10.5 : 14,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _dividerV() =>
      Container(width: 1, height: 36, color: const Color(0xFFE5E7EB));

  Widget _loadingWidget() => const Center(
    child: CircularProgressIndicator(color: _primary, strokeWidth: 2.5),
  );

  Widget _errorWidget(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
          const SizedBox(height: 8),
          const Text(
            'Error loading data',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            msg,
            style: const TextStyle(color: _textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _emptyWidget(String msg) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.inbox_rounded,
          color: _textSecondary.withOpacity(0.4),
          size: 52,
        ),
        const SizedBox(height: 10),
        Text(
          msg,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  // ── Dialogs ─────────────────────────────────────

  void _showPaymentDetails(
    BuildContext ctx,
    Map<String, dynamic> d,
    String docId,
  ) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Transaction Details',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Divider(height: 24),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _detailRow('Order ID', d['orderId'] ?? docId),
                    _detailRow('Payment ID', d['paymentId'] ?? '—'),
                    _detailRow('Sender', d['senderName'] ?? '—'),
                    _detailRow('Receiver', d['receiverName'] ?? '—'),
                    _detailRow('Receiver Ph.', d['receiverPhone'] ?? '—'),
                    _detailRow('Traveler', d['travelerName'] ?? '—'),
                    _detailRow('Amount', _fmt(_toDouble(d['price']))),
                    _detailRow(
                      'Status',
                      (d['paymentStatus'] ?? '—').toString(),
                    ),
                    _detailRow('Date', _formatTs(d['paidAt'])),
                    _detailRow('Pickup', d['pickup']?['address'] ?? '—'),
                    _detailRow('Delivery', d['drop']?['address'] ?? '—'),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAction({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: _textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(
              confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }
}

// ── Data class ──────────────────────────────────

class _SummaryCard {
  final String label, amount, sub;
  final IconData icon;
  final Color color, bg;

  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    required this.bg,
    required this.sub,
  });
}
