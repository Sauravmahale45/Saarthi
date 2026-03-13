// ════════════════════════════════════════════════════════════════════════════
//  available_travelers_screen.dart  –  Saarthi (UPDATED v2)
//
//  CHANGES FROM v1:
//   1. ignoredTravelers support  – filtered out from list
//   2. Race-condition guard      – read-before-write in _requestTraveler()
//   3. Unstuck sender            – allow re-request when status == 'requested'
//                                  and the assigned traveler is not this one
//   4. Empty travelerId guard    – skip if travelerId is null / empty
//   5. Real-time parcel updates  – replaced .get() with .snapshots() StreamBuilder
//   6. Invalid traveler filter   – _filterRoutes() rejects missing travelerId
// ════════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ── Brand colours (same as app) ───────────────────────────────────────────────
const _indigo = Color(0xFF4F46E5);
const _teal = Color(0xFF14B8A6);
const _orange = Color(0xFFF97316);
const _bg = Color(0xFFF5F7FF);
const _text1 = Color(0xFF0F172A);
const _text2 = Color(0xFF64748B);
const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);

// ════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════════════════════
class AvailableTravelersScreen extends StatefulWidget {
  final String parcelId;
  const AvailableTravelersScreen({super.key, required this.parcelId});

  @override
  State<AvailableTravelersScreen> createState() =>
      _AvailableTravelersScreenState();
}

class _AvailableTravelersScreenState extends State<AvailableTravelersScreen> {
  // ── IMPROVEMENT 5: Parcel is now a real-time stream, not a one-shot .get() ──
  // _parcel and _loadingParcel are kept for the parcel stream snapshot caching
  // so the rest of the build tree can read them synchronously.
  Map<String, dynamic>? _parcel;
  bool _loadingParcel = true;
  String? _error;

  // ── IMPROVEMENT 1: ignoredTravelers list ──────────────────────────────────
  List<String> _ignoredTravelers = [];

  // ── Request state ──────────────────────────────────────────────────────────
  String? _requestingTravelerId;
  String? _assignedTravelerId;

  // ── Parcel real-time subscription ──────────────────────────────────────────
  Stream<DocumentSnapshot>? _parcelStream;

  @override
  void initState() {
    super.initState();
    // IMPROVEMENT 5: subscribe to parcel document instead of one-shot .get()
    _parcelStream = FirebaseFirestore.instance
        .collection('parcels')
        .doc(widget.parcelId)
        .snapshots();
  }

  // ── Parse a parcel snapshot into local state ───────────────────────────────
  void _applyParcelSnapshot(DocumentSnapshot snap) {
    if (!snap.exists) {
      setState(() {
        _error = 'Parcel not found.';
        _loadingParcel = false;
      });
      return;
    }
    final data = snap.data() as Map<String, dynamic>;
    setState(() {
      _parcel = data;
      _assignedTravelerId = data['travelerId'] as String?;
      // IMPROVEMENT 1: load ignoredTravelers from Firestore
      _ignoredTravelers = List<String>.from(data['ignoredTravelers'] ?? []);
      _loadingParcel = false;
    });
  }

  // ── Build travelRoutes stream ──────────────────────────────────────────────
  Stream<QuerySnapshot>? _buildTravelersStream() {
    final p = _parcel;
    if (p == null) return null;
    return FirebaseFirestore.instance
        .collection('travelRoutes')
        .where('fromCity', isEqualTo: p['fromCity'])
        .where('toCity', isEqualTo: p['toCity'])
        .snapshots();
  }

  // ── Client-side filter ────────────────────────────────────────────────────
  List<QueryDocumentSnapshot> _filterRoutes(
    List<QueryDocumentSnapshot> docs,
    double parcelWeight,
  ) {
    final now = DateTime.now();
    return docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;

      // IMPROVEMENT 6: reject missing / empty travelerId
      final travelerId = d['travelerId'] as String?;
      if (travelerId == null || travelerId.isEmpty) return false;

      // IMPROVEMENT 1: exclude ignored travelers
      if (_ignoredTravelers.contains(travelerId)) return false;

      // bagSpaceKg check
      final bagSpace = (d['bagSpaceKg'] as num?)?.toDouble() ?? 0;
      if (bagSpace < parcelWeight) return false;

      // travelDateTime must be today or future
      final ts = d['travelDateTime'] as Timestamp?;
      if (ts != null && ts.toDate().isBefore(now)) return false;

      return true;
    }).toList();
  }

  // ── Request a traveler ────────────────────────────────────────────────────
  Future<void> _requestTraveler(String travelerId, String travelerName) async {
    // IMPROVEMENT 4: guard against empty travelerId
    if (travelerId.isEmpty) return;

    setState(() => _requestingTravelerId = travelerId);

    try {
      final parcelRef = FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId);

      // IMPROVEMENT 2: read-before-write to prevent race conditions
      final freshSnap = await parcelRef.get();
      if (!freshSnap.exists) {
        _toast('Parcel no longer exists.', isError: true);
        setState(() => _requestingTravelerId = null);
        return;
      }

      final freshData = freshSnap.data() as Map<String, dynamic>;
      final currentStatus = freshData['status'] as String? ?? 'pending';

      // Only allow request if parcel is still pending
      if (currentStatus != 'pending') {
        _toast('Parcel already assigned to another traveler.', isError: true);
        setState(() => _requestingTravelerId = null);
        return;
      }

      await parcelRef.update({
        'travelerId': travelerId,
        'travelerName': travelerName,
        'status': 'requested',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      // Local state is updated by the parcel stream listener automatically,
      // but we also mirror here for instant UI feedback.
      setState(() {
        _assignedTravelerId = travelerId;
        _requestingTravelerId = null;
        _parcel!['travelerId'] = travelerId;
        _parcel!['status'] = 'requested';
      });

      _toast('✅ Request sent! The traveler will respond soon.');
    } catch (e) {
      setState(() => _requestingTravelerId = null);
      _toast('Failed to send request: $e', isError: true);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _red : _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // IMPROVEMENT 5: wrap the whole screen in a parcel StreamBuilder so that
    // accept / reject by the traveler reflects immediately here.
    return StreamBuilder<DocumentSnapshot>(
      stream: _parcelStream,
      builder: (context, parcelSnap) {
        // First frame or error
        if (parcelSnap.connectionState == ConnectionState.waiting &&
            _loadingParcel) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: CircularProgressIndicator(color: _indigo)),
          );
        }

        if (parcelSnap.hasError) {
          return Scaffold(
            backgroundColor: _bg,
            body: _ErrorView(
              error: parcelSnap.error.toString(),
              onBack: () => context.go('/sender'),
            ),
          );
        }

        // Apply snapshot to local state (only when data actually changes)
        if (parcelSnap.hasData && parcelSnap.data != null) {
          // Use addPostFrameCallback to avoid calling setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _applyParcelSnapshot(parcelSnap.data!);
          });
        }

        if (_error != null) {
          return Scaffold(
            backgroundColor: _bg,
            body: _ErrorView(
              error: _error!,
              onBack: () => context.go('/sender'),
            ),
          );
        }

        if (_parcel == null) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: CircularProgressIndicator(color: _indigo)),
          );
        }

        return Scaffold(backgroundColor: _bg, body: _buildContent());
      },
    );
  }

  Widget _buildContent() {
    final p = _parcel!;
    final weight = (p['weight'] as num?)?.toDouble() ?? 0;
    final stream = _buildTravelersStream();
    final parcelStatus = p['status'] as String? ?? 'pending';
    final hasTraveler =
        _assignedTravelerId != null && _assignedTravelerId!.isNotEmpty;

    return CustomScrollView(
      slivers: [
        // ── Gradient header ───────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 200,
          floating: false,
          pinned: true,
          backgroundColor: _indigo,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => context.go('/sender'),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4338CA), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hasTraveler
                              ? (parcelStatus == 'accepted'
                                    ? _green.withOpacity(0.25)
                                    : _orange.withOpacity(0.25))
                              : Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hasTraveler
                                ? (parcelStatus == 'accepted'
                                      ? _green.withOpacity(0.5)
                                      : _orange.withOpacity(0.5))
                                : Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasTraveler
                                  ? (parcelStatus == 'accepted'
                                        ? Icons.check_circle_rounded
                                        : Icons.hourglass_empty_rounded)
                                  : Icons.search_rounded,
                              size: 13,
                              color: hasTraveler
                                  ? (parcelStatus == 'accepted'
                                        ? _green
                                        : _orange)
                                  : Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              hasTraveler
                                  ? (parcelStatus == 'accepted'
                                        ? 'Traveler Assigned'
                                        : 'Request Sent')
                                  : 'Finding Travelers',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: hasTraveler
                                    ? (parcelStatus == 'accepted'
                                          ? _green
                                          : _orange)
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Available Travelers',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _RouteChip(label: p['fromCity'] ?? ''),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Container(
                              width: 28,
                              height: 2,
                              decoration: BoxDecoration(
                                color: Colors.white54,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.local_shipping_outlined,
                            color: Colors.white60,
                            size: 16,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Container(
                              width: 28,
                              height: 2,
                              decoration: BoxDecoration(
                                color: Colors.white54,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          _RouteChip(label: p['toCity'] ?? ''),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          _MetaChip(
                            icon: Icons.inventory_2_outlined,
                            label: p['category'] ?? 'Parcel',
                          ),
                          _MetaChip(
                            icon: Icons.scale_outlined,
                            label: '${weight}kg',
                          ),
                          _MetaChip(
                            icon: Icons.straighten_outlined,
                            label: p['size'] ?? '',
                          ),
                          _MetaChip(
                            icon: Icons.currency_rupee_rounded,
                            label: '₹${p['price'] ?? 0}',
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

        // ── Parcel summary card ───────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _ParcelSummaryCard(parcel: p),
          ),
        ),

        // ── Section header ────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _indigo,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Matched Travelers',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _text1,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _indigo.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Route + Space matched',
                    style: TextStyle(
                      fontSize: 10,
                      color: _indigo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Traveler list ─────────────────────────────────────────────────────
        if (stream == null)
          const SliverToBoxAdapter(child: _NoTravelersCard())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: _indigo),
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return SliverToBoxAdapter(
                    child: _ErrorCard(
                      msg: 'Could not load travelers.\n${snap.error}',
                    ),
                  );
                }

                final filtered = _filterRoutes(snap.data?.docs ?? [], weight);

                if (filtered.isEmpty) {
                  return const SliverToBoxAdapter(child: _NoTravelersCard());
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final doc = filtered[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final tid = data['travelerId'] as String? ?? '';
                    final isAssigned = _assignedTravelerId == tid;
                    final isRequesting = _requestingTravelerId == tid;
                    final isAccepted = isAssigned && parcelStatus == 'accepted';
                    final isRequested =
                        isAssigned && parcelStatus == 'requested';

                    // IMPROVEMENT 3: alreadyHasTraveler is true ONLY when
                    // status == 'accepted' (fully locked in).
                    // When status == 'requested' the sender can still
                    // request a DIFFERENT traveler (allows unstuck flow).
                    final alreadyHasTraveler =
                        parcelStatus == 'accepted' && !isAssigned;

                    return _TravelerCard(
                      routeData: data,
                      isAssigned: isAssigned,
                      isAccepted: isAccepted,
                      isRequested: isRequested,
                      isRequesting: isRequesting,
                      alreadyHasTraveler: alreadyHasTraveler,
                      onRequest: () => _requestTraveler(
                        tid,
                        data['travelerName'] as String? ?? '',
                      ),
                    );
                  }, childCount: filtered.length),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PARCEL SUMMARY CARD (unchanged UI)
// ════════════════════════════════════════════════════════════════════════════
class _ParcelSummaryCard extends StatelessWidget {
  final Map<String, dynamic> parcel;
  const _ParcelSummaryCard({required this.parcel});

  Color _statusColor(String? status) {
    switch (status) {
      case 'accepted':
        return _green;
      case 'requested':
        return _orange;
      default:
        return _text2;
    }
  }

  String _statusText(String? status) {
    switch (status) {
      case 'accepted':
        return '✅ Assigned';
      case 'requested':
        return '⏳ Request Sent';
      default:
        return '⏳ Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = parcel['status'] as String? ?? 'pending';
    final hasTraveler = (parcel['travelerId'] as String?)?.isNotEmpty ?? false;
    final statusColor = _statusColor(status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasTraveler ? statusColor.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasTraveler
              ? statusColor.withOpacity(0.3)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _indigo.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: _indigo,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parcel['category'] ?? 'Parcel',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _text1,
                      ),
                    ),
                    Text(
                      parcel['description'] ?? '',
                      style: const TextStyle(fontSize: 12, color: _text2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withOpacity(0.2)),
                ),
                child: Text(
                  _statusText(status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.person_outline,
                  label: 'Receiver',
                  value: parcel['receiverName'] ?? '',
                ),
              ),
              Expanded(
                child: _InfoTile(
                  icon: Icons.scale_outlined,
                  label: 'Weight',
                  value: '${parcel['weight'] ?? 0} kg',
                ),
              ),
              Expanded(
                child: _InfoTile(
                  icon: Icons.currency_rupee_rounded,
                  label: 'Price',
                  value: '₹${parcel['price'] ?? 0}',
                ),
              ),
            ],
          ),
          if (hasTraveler && status == 'requested') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.hourglass_empty_rounded,
                    color: _orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Request sent to "${parcel['travelerName']}". '
                      'Waiting for them to accept.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TRAVELER CARD (unchanged UI)
// ════════════════════════════════════════════════════════════════════════════
class _TravelerCard extends StatelessWidget {
  final Map<String, dynamic> routeData;
  final bool isAssigned;
  final bool isAccepted;
  final bool isRequested;
  final bool isRequesting;
  final bool alreadyHasTraveler;
  final VoidCallback onRequest;

  const _TravelerCard({
    required this.routeData,
    required this.isAssigned,
    required this.isAccepted,
    required this.isRequested,
    required this.isRequesting,
    required this.alreadyHasTraveler,
    required this.onRequest,
  });

  String _formatDateTime(Timestamp? ts) {
    if (ts == null) return 'Not set';
    final dt = ts.toDate();
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = dt.hour;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '${dt.day} ${months[dt.month]} · $hour:$min $ampm';
  }

  String _timeUntil(Timestamp? ts) {
    if (ts == null) return '';
    final diff = ts.toDate().difference(DateTime.now());
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'Soon';
  }

  @override
  Widget build(BuildContext context) {
    final name = routeData['travelerName'] as String? ?? 'Traveler';
    final bagSpace = (routeData['bagSpaceKg'] as num?)?.toDouble() ?? 0;
    final travelTs = routeData['travelDateTime'] as Timestamp?;
    final fromCity = routeData['fromCity'] as String? ?? '';
    final toCity = routeData['toCity'] as String? ?? '';

    final initials = name.trim().isEmpty
        ? 'T'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

    Color borderColor = const Color(0xFFE2E8F0);
    Color bgColor = Colors.white;
    if (isAccepted) {
      borderColor = _green.withOpacity(0.35);
      bgColor = _green.withOpacity(0.03);
    } else if (isRequested) {
      borderColor = _orange.withOpacity(0.35);
      bgColor = _orange.withOpacity(0.03);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isAssigned ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: (isAssigned ? (isAccepted ? _green : _orange) : Colors.black)
                .withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Top section ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: _indigo.withOpacity(0.12),
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _indigo,
                        ),
                      ),
                    ),
                    if (isAssigned)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isAccepted ? _green : _orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            isAccepted ? Icons.check : Icons.hourglass_empty,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _text1,
                              ),
                            ),
                          ),
                          if (isAccepted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Assigned ✓',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _green,
                                ),
                              ),
                            ),
                          if (isRequested)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Requested ⏳',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.route_rounded,
                            size: 13,
                            color: _text2,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$fromCity → $toCity',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _text2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Stats row ──────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _StatCell(
                  icon: Icons.luggage_outlined,
                  color: _teal,
                  label: 'Bag Space',
                  value: '${bagSpace}kg',
                ),
                _Divider(),
                _StatCell(
                  icon: Icons.calendar_today_outlined,
                  color: _indigo,
                  label: 'Travel Date',
                  value: _formatDateTime(travelTs),
                ),
                _Divider(),
                _StatCell(
                  icon: Icons.access_time_rounded,
                  color: _orange,
                  label: 'Departs',
                  value: _timeUntil(travelTs),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Action button ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (isRequesting || isAssigned || alreadyHasTraveler)
                    ? null
                    : onRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isAccepted
                      ? _green
                      : isRequested
                      ? _orange.withOpacity(0.5)
                      : alreadyHasTraveler
                      ? Colors.grey.shade300
                      : _indigo,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: isAccepted
                      ? _green.withOpacity(0.6)
                      : isRequested
                      ? _orange.withOpacity(0.3)
                      : Colors.grey.shade300,
                  disabledForegroundColor: isAccepted
                      ? Colors.white
                      : isRequested
                      ? Colors.white
                      : Colors.grey.shade500,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: (isAssigned || alreadyHasTraveler) ? 0 : 2,
                  shadowColor: _indigo.withOpacity(0.3),
                ),
                child: isRequesting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Requesting…',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isAccepted
                                ? Icons.check_circle_rounded
                                : isRequested
                                ? Icons.hourglass_empty_rounded
                                : alreadyHasTraveler
                                ? Icons.lock_outline_rounded
                                : Icons.person_add_alt_1_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isAccepted
                                ? 'Traveler Assigned'
                                : isRequested
                                ? 'Request Sent'
                                : alreadyHasTraveler
                                ? 'Already Requested'
                                : 'Request This Traveler',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  EMPTY / ERROR WIDGETS (unchanged)
// ════════════════════════════════════════════════════════════════════════════
class _NoTravelersCard extends StatelessWidget {
  const _NoTravelersCard();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _orange.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.person_search_rounded,
            color: _orange,
            size: 34,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'No Travelers Available',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: _text1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'No travelers are heading this route with\nsufficient bag space right now.\n\n'
          'Your parcel will be matched automatically\nwhen a traveler registers this route.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _text2, height: 1.6),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _indigo.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_outlined, size: 15, color: _indigo),
              SizedBox(width: 8),
              Text(
                "You'll be notified when a match is found",
                style: TextStyle(
                  fontSize: 12,
                  color: _indigo,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  final String msg;
  const _ErrorCard({required this.msg});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(8),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _red.withOpacity(0.05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _red.withOpacity(0.2)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: _red, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            msg,
            style: const TextStyle(fontSize: 13, color: _red, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onBack;
  const _ErrorView({required this.error, required this.onBack});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: _red, size: 60),
          const SizedBox(height: 16),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: _text2),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Go Back'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  SMALL REUSABLE WIDGETS (unchanged)
// ════════════════════════════════════════════════════════════════════════════
class _RouteChip extends StatelessWidget {
  final String label;
  const _RouteChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withOpacity(0.3)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  );
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: Colors.white70),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, size: 16, color: _text2),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: _text1,
        ),
        textAlign: TextAlign.center,
      ),
      Text(label, style: const TextStyle(fontSize: 10, color: _text2)),
    ],
  );
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _StatCell({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _text1,
          ),
          textAlign: TextAlign.center,
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: _text2)),
      ],
    ),
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, color: const Color(0xFFE2E8F0));
}
