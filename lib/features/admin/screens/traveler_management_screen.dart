import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'traveler_kyc_details_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRAVELER MANAGEMENT SCREEN  –  KYC Admin Panel
//
// Firestore queries
// ─────────────────────────────────────────────────────────────────────────────
//
//  All Travelers tab:
//    collection("users").where("role", isEqualTo: "traveler")
//
//  KYC Requests tab:
//    collection("users")
//      .where("role",      isEqualTo: "traveler")
//      .where("kycStatus", isEqualTo: "submitted")
//
// ⚠️  The two-field KYC query REQUIRES a Firestore composite index:
//       Collection : users
//       Fields     : role ASC  +  kycStatus ASC
//     Create it at:
//       Firebase Console → Firestore → Indexes → Composite → Add index
//     Or paste this into firestore.indexes.json and run `firebase deploy --only firestore`:
//       {
//         "indexes": [{
//           "collectionGroup": "users",
//           "queryScope": "COLLECTION",
//           "fields": [
//             { "fieldPath": "role",      "order": "ASCENDING" },
//             { "fieldPath": "kycStatus", "order": "ASCENDING" }
//           ]
//         }]
//       }
// ─────────────────────────────────────────────────────────────────────────────

class TravelerManagementScreen extends StatefulWidget {
  const TravelerManagementScreen({super.key});

  @override
  State<TravelerManagementScreen> createState() =>
      _TravelerManagementScreenState();
}

class _TravelerManagementScreenState extends State<TravelerManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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

  // ── Firestore KYC status update ──────────────────────────────────────────

  Future<void> _updateKycStatus({
    required String uid,
    required bool verified,
    required String status,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'kycVerified'  : verified,
        'kycStatus'    : status,   // admin alias
        'status'       : status,   // form field — keep in sync so queries match
        'kycReviewedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _showToast(
        verified ? 'KYC Approved ✓' : 'KYC Rejected',
        verified ? _AppColors.success : _AppColors.danger,
      );
    } catch (e) {
      if (!mounted) return;
      _showToast('Update failed: $e', _AppColors.danger);
    }
  }

  void _showToast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Firestore stream helpers ─────────────────────────────────────────────

  /// All Travelers tab — streams all users and filters client-side so
  /// travelers appear even if role field is missing, differently cased, or
  /// uses a different value than expected.
  Stream<QuerySnapshot> get _allTravelersStream =>
      FirebaseFirestore.instance
          .collection('users')
          .snapshots(); // filter client-side below

  /// Returns true when a doc belongs to a traveler (any casing / value).
  bool _isTraveler(Map<String, dynamic> data) {
    final role = (data['role'] as String? ?? '').toLowerCase().trim();
    // Accept "traveler", "Traveler", "TRAVELER", or docs with no role but
    // with KYC fields present (form-submitted docs that skipped role write)
    return role == 'traveler' ||
           data['documentUrl'] != null ||
           data['selfieUrl']   != null ||
           data['kycStatus']   != null ||
           data['status']      != null;
  }

  /// KYC Requests tab — streams the ENTIRE users collection with NO server
  /// filter.  All filtering is done client-side in [_isPendingKyc] so the
  /// screen works regardless of:
  ///   • whether the KYC form wrote role="traveler" at all
  ///   • which field name was used: "status" vs "kycStatus"
  ///   • casing differences ("Traveler" vs "traveler")
  ///   • missing composite Firestore indexes
  Stream<QuerySnapshot> get _kycRequestsStream =>
      FirebaseFirestore.instance
          .collection('users')
          .snapshots(); // NO server filter — client-side only

  /// Returns true when a user document is a pending KYC submission.
  /// Checks every possible field+value combination the form might write.
  bool _isPendingKyc(Map<String, dynamic> data) {
    final status    = (data['status']    as String? ?? '').toLowerCase().trim();
    final kycStatus = (data['kycStatus'] as String? ?? '').toLowerCase().trim();
    const pending   = {'submitted', 'requested', 'pending'};
    // Must have at least one of the KYC document URLs to be a real submission
    final hasDoc    = (data['documentUrl'] as String? ?? '').isNotEmpty ||
                      (data['govIdUrl']    as String? ?? '').isNotEmpty;
    return (pending.contains(status) || pending.contains(kycStatus)) && hasDoc;
  }

  // ─── KYC Requests Tab ───────────────────────────────────────────────────

  Widget _kycRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _kycRequestsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (kDebugMode) {
            debugPrint('KYC Requests error: ${snapshot.error}');
          }
          // Surface a human-readable hint when the composite index is missing
          final msg = snapshot.error.toString().toLowerCase().contains('index')
              ? 'Missing Firestore composite index.\n\n'
                'Go to Firebase Console → Firestore → Indexes\n'
                'and add: users → role ASC + kycStatus ASC'
              : snapshot.error.toString();
          return _errorState(msg);
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Client-side filter — no role/status server filter needed
        final allDocs     = snapshot.data?.docs ?? [];

        if (kDebugMode) {
          debugPrint('KYC stream: total docs=${allDocs.length}');
          for (final d in allDocs) {
            final data = (d.data() as Map<String, dynamic>?) ?? {};
            debugPrint(
              '  doc=${d.id} '
              'role=${data["role"]} '
              'status=${data["status"]} '
              'kycStatus=${data["kycStatus"]} '
              'docUrl=${(data["documentUrl"] as String? ?? "").isNotEmpty}',
            );
          }
        }

        final pendingDocs = allDocs.where((d) {
          final data = (d.data() as Map<String, dynamic>?) ?? {};
          return _isPendingKyc(data);
        }).toList();

        if (kDebugMode) {
          debugPrint('KYC stream: pendingDocs=${pendingDocs.length}');
        }

        if (pendingDocs.isEmpty) {
          return _emptyState(
            icon:     Icons.verified_user_outlined,
            title:    'No pending KYC requests',
            subtitle: 'All submissions have been reviewed.',
          );
        }

        return ListView.separated(
          padding:           const EdgeInsets.all(20),
          itemCount:         pendingDocs.length,
          separatorBuilder:  (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final doc  = pendingDocs[i];
            final data = (doc.data() as Map<String, dynamic>?) ?? {};
            return _KycRequestCard(
              data:          data,
              docId:         doc.id,
              onVerify:      () => _updateKycStatus(
                uid: doc.id, verified: true, status: 'approved'),
              onReject:      () => _confirmReject(doc.id),
              onViewDetails: () => _openDetails(doc),
            );
          },
        );
      },
    );
  }

  // ─── All Travelers Tab ───────────────────────────────────────────────────

  Widget _allTravelersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _allTravelersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (kDebugMode) debugPrint('All Travelers error: ${snapshot.error}');
          return _errorState(snapshot.error.toString());
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Client-side filter — keep only traveler documents
        final allUsers = snapshot.data?.docs ?? [];
        final docs     = allUsers.where((d) {
          final data = (d.data() as Map<String, dynamic>?) ?? {};
          return _isTraveler(data);
        }).toList();

        if (docs.isEmpty) {
          return _emptyState(
            icon:     Icons.people_outline,
            title:    'No travelers yet',
            subtitle: 'Registered travelers will appear here.',
          );
        }

        // Compute stats — check both "status" (form field) and "kycStatus" (alias)
        int verified = 0, pending = 0, rejected = 0;
        for (final d in docs) {
          final data      = (d.data() as Map<String, dynamic>?) ?? {};
          final status    = data['status']    as String? ?? '';
          final kycStatus = data['kycStatus'] as String? ?? '';
          final either    = status.isNotEmpty ? status : kycStatus;
          if (data['kycVerified'] == true)                          verified++;
          if (either == 'submitted' || either == 'requested')       pending++;
          if (either == 'rejected')                                  rejected++;
        }

        return Column(
          children: [
            _StatsBar(
              total:    docs.length,
              verified: verified,
              pending:  pending,
              rejected: rejected,
            ),
            Expanded(
              child: ListView.separated(
                padding:          const EdgeInsets.fromLTRB(20, 8, 20, 20),
                itemCount:        docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final doc  = docs[i];
                  final data = (doc.data() as Map<String, dynamic>?) ?? {};
                  return _TravelerRowCard(
                    data:          data,
                    onViewDetails: () => _openDetails(doc),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Navigation / dialogs ────────────────────────────────────────────────

  void _openDetails(QueryDocumentSnapshot doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TravelerKycDetailsScreen(
          travelerId:   doc.id,
          travelerData: (doc.data() as Map<String, dynamic>?) ?? {},
        ),
      ),
    );
  }

  Future<void> _confirmReject(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject KYC?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            "This will mark the traveler's KYC as rejected. "
            'They will need to resubmit documents.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:     const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child:     const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _updateKycStatus(uid: uid, verified: false, status: 'rejected');
    }
  }

  // ─── Reusable states ─────────────────────────────────────────────────────

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline,
              color: _AppColors.danger, size: 48),
          const SizedBox(height: 12),
          Text('Something went wrong.',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.grey[800])),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(title,
            style: TextStyle(
                fontSize:   16,
                fontWeight: FontWeight.bold,
                color:      Colors.grey[700])),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      ]),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1D23),
        elevation:       0,
        surfaceTintColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Traveler Management',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('KYC Administration Panel',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
        bottom: TabBar(
          controller:            _tabController,
          labelColor:            _AppColors.primary,
          unselectedLabelColor:  Colors.grey[500],
          indicatorColor:        _AppColors.primary,
          indicatorWeight:       3,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'KYC Requests'),
            Tab(text: 'All Travelers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _kycRequestsTab(),
          _allTravelersTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KYC REQUEST CARD
// Reads the flat Firestore schema fields directly from the data map.
// ─────────────────────────────────────────────────────────────────────────────

class _KycRequestCard extends StatelessWidget {
  const _KycRequestCard({
    required this.data,
    required this.docId,
    required this.onVerify,
    required this.onReject,
    required this.onViewDetails,
  });

  final Map<String, dynamic> data;
  final String docId;
  final VoidCallback onVerify;
  final VoidCallback onReject;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    // Fields written by the traveler KYC submission form (see screenshots)
    final String     name        = _s(data['fullName'],     _s(data['name'], 'Unknown'));
    final String     email       = _s(data['email'],        '');
    final String     dateOfBirth = _s(data['dateOfBirth'],  '');
    final String     address     = _s(data['address'],      '');
    final String     docType     = _s(data['documentType'], '');
    final String?    photo       = _url(data['photoUrl']);
    final Timestamp? submittedAt = data['submittedAt'] as Timestamp?;

    return Container(
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: const Color(0xFFE8ECF4)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Amber header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color:        Color(0xFFFFF8F0),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.pending_actions,
                  size: 14, color: Color(0xFFE67E22)),
              const SizedBox(width: 6),
              Text('KYC Pending Review',
                  style: TextStyle(
                      fontSize:   11,
                      color:      Colors.orange[700],
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (submittedAt != null)
                Text(_formatDate(submittedAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ),

          // ── Profile info ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(photo: photo, name: name, radius: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      if (email.isNotEmpty)
                        _InfoRow(icon: Icons.email_outlined,         value: email),
                      if (dateOfBirth.isNotEmpty)
                        _InfoRow(icon: Icons.cake_outlined,          value: 'DOB: $dateOfBirth'),
                      if (address.isNotEmpty)
                        _InfoRow(icon: Icons.location_on_outlined,   value: address),
                      if (docType.isNotEmpty)
                        _InfoRow(icon: Icons.credit_card_outlined,   value: docType),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFEEF0F6)),

          // ── Action buttons ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: _ActionButton(
                  label: 'Verify',
                  icon:  Icons.check_circle_outline,
                  color: _AppColors.success,
                  onTap: onVerify,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Reject',
                  icon:  Icons.cancel_outlined,
                  color: _AppColors.danger,
                  onTap: onReject,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label:    'Details',
                  icon:     Icons.open_in_new_rounded,
                  color:    _AppColors.primary,
                  outlined: true,
                  onTap:    onViewDetails,
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALL-TRAVELERS ROW CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TravelerRowCard extends StatelessWidget {
  const _TravelerRowCard({
    required this.data,
    required this.onViewDetails,
  });

  final Map<String, dynamic> data;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final String  name     = _s(data['fullName'],  _s(data['name'], 'Unknown'));
    final String  email    = _s(data['email'],     '');
    final bool    verified = data['kycVerified'] == true;
    // API/form uses "status"; Firestore admin panel uses "kycStatus"
    final String  status   = _s(data['kycStatus'], _s(data['status'], 'not_submitted'));
    final String? photo    = _url(data['photoUrl']);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: const Color(0xFFEEF0F6)),
      ),
      child: Row(children: [
        _Avatar(photo: photo, name: name, radius: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
              if (email.isNotEmpty)
                Text(email,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _KycBadge(verified: verified, status: status),
        const SizedBox(width: 8),
        InkWell(
          onTap:        onViewDetails,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.chevron_right,
                color: Colors.grey[400], size: 20),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS BAR
// ─────────────────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.total,
    required this.verified,
    required this.pending,
    required this.rejected,
  });

  final int total, verified, pending, rejected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(children: [
        _StatChip(label: 'Total',    value: total,    color: _AppColors.primary,           bg: const Color(0xFFEEF2FF)),
        const SizedBox(width: 8),
        _StatChip(label: 'Verified', value: verified, color: _AppColors.success,           bg: const Color(0xFFE8F5E9)),
        const SizedBox(width: 8),
        _StatChip(label: 'Pending',  value: pending,  color: const Color(0xFFE67E22),      bg: const Color(0xFFFFF3E0)),
        const SizedBox(width: 8),
        _StatChip(label: 'Rejected', value: rejected, color: _AppColors.danger,            bg: const Color(0xFFFFEBEE)),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
  });

  final String label;
  final int    value;
  final Color  color, bg;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$value',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar(
      {required this.photo, required this.name, required this.radius});

  final String? photo;
  final String  name;
  final double  radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius:          radius,
      backgroundColor: const Color(0xFFE8ECF4),
      backgroundImage: photo != null ? NetworkImage(photo!) : null,
      child: photo == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:   radius * 0.7,
                  color:      _AppColors.primary),
            )
          : null,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value});

  final IconData icon;
  final String   value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Icon(icon, size: 13, color: Colors.grey[500]),
        const SizedBox(width: 5),
        Expanded(
          child: Text(value,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  final String   label;
  final IconData icon;
  final Color    color;
  final VoidCallback onTap;
  final bool     outlined;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: outlined
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side:    BorderSide(color: color),
                shape:   RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: EdgeInsets.zero,
              ),
              onPressed: onTap,
              icon:  Icon(icon, size: 14),
              label: Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            )
          : ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation:       0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: EdgeInsets.zero,
              ),
              onPressed: onTap,
              icon:  Icon(icon, size: 14),
              label: Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
    );
  }
}

class _KycBadge extends StatelessWidget {
  const _KycBadge({required this.verified, required this.status});

  final bool   verified;
  final String status;

  @override
  Widget build(BuildContext context) {
    late Color  bg, fg;
    late String label;

    if (verified) {
      bg = const Color(0xFFE8F5E9); fg = _AppColors.success;      label = 'Verified';
    } else if (status == 'submitted' || status == 'requested') {
      bg = const Color(0xFFFFF3E0); fg = const Color(0xFFE67E22); label = 'Pending';
    } else if (status == 'rejected') {
      bg = const Color(0xFFFFEBEE); fg = _AppColors.danger;       label = 'Rejected';
    } else {
      bg = const Color(0xFFF5F5F5); fg = Colors.grey;             label = 'Not Submitted';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

String _s(dynamic v, String fallback) =>
    (v is String && v.trim().isNotEmpty) ? v.trim() : fallback;

String? _url(dynamic v) =>
    (v is String && v.trim().isNotEmpty) ? v.trim() : null;

String _formatDate(Timestamp ts) {
  final dt = ts.toDate().toLocal();
  const months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

abstract class _AppColors {
  static const Color primary = Color(0xFF3B5BDB);
  static const Color success = Color(0xFF2E7D32);
  static const Color danger  = Color(0xFFC62828);
}