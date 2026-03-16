import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TravelerManagementScreen extends StatelessWidget {
  const TravelerManagementScreen({super.key});

  // ---------------------------------------------------------------------------
  // FIRESTORE UPDATE
  // ---------------------------------------------------------------------------

  Future<void> _updateKycStatus({
    required String uid,
    required bool verified,
    required String status,
    required BuildContext context,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'kycVerified': verified, 'kycStatus': status});
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // STATUS CHIP
  // ---------------------------------------------------------------------------

  Widget _statusChip(bool verified) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: verified ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        verified ? 'Verified' : 'Pending',
        style: TextStyle(
          color: verified
              ? const Color(0xFF2E7D32)
              : const Color(0xFFE65100),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STAT CARD
  // ---------------------------------------------------------------------------

  Widget _statCard(
    String number,
    String label,
    Color bg,
    Color textColor, {
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              number,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: textColor),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TRAVELER CARD
  //
  // FIX (infinite width + null crash): every button is wrapped in Expanded so
  // the Row never tries to measure an intrinsically-unsized ElevatedButton in
  // an unbounded horizontal context.
  //
  // FIX (null crash): all Color values are hardcoded constants — no .shade
  // accessors that can return null at runtime.
  // ---------------------------------------------------------------------------

  Widget _travelerCard(BuildContext context, QueryDocumentSnapshot doc) {
    // Safe cast — always succeeds for Firestore docs
    final Map<String, dynamic> data =
        (doc.data() as Map<String, dynamic>?) ?? {};

    final String uid = doc.id;

    if (kDebugMode) {
      debugPrint('TravelerCard [$uid] data: $data');
    }

    final String name =
        data['name'] is String ? data['name'] as String : 'Unknown';
    final String phone =
        data['phone'] is String ? data['phone'] as String : '';
    final String city =
        data['city'] is String ? data['city'] as String : '';
    final bool verified = data['kycVerified'] == true;

    final num ratingRaw =
        data['rating'] is num ? data['rating'] as num : 0;
    final double rating = ratingRaw.toDouble();

    final String? photo =
        (data['photoUrl'] is String &&
                (data['photoUrl'] as String).trim().isNotEmpty)
            ? (data['photoUrl'] as String).trim()
            : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      // FIX: give the card an explicit finite width so its children are
      // never measured in an unbounded context.
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            color: Color(0x1A000000),
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- USER INFO ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // FIX: CircleAvatar with a safe fallback when photo is null
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE0E0E0),
                backgroundImage:
                    photo != null ? NetworkImage(photo) : null,
                child: photo == null
                    ? const Icon(Icons.person, color: Color(0xFF9E9E9E))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (city.isNotEmpty)
                      Text('City: $city',
                          overflow: TextOverflow.ellipsis),
                    if (phone.isNotEmpty)
                      Text('Phone: $phone',
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(verified),
            ],
          ),

          const SizedBox(height: 10),

          // ---- RATING ----
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 16),
              const SizedBox(width: 4),
              Text('Rating ${rating.toStringAsFixed(1)}'),
            ],
          ),

          const Divider(height: 20),

          // ---- ACTION BUTTONS ----
          // FIX (BoxConstraints infinite width): ElevatedButton has no
          // intrinsic width; placing it directly in a Row with
          // MainAxisAlignment.spaceBetween in an unconstrained context
          // throws "BoxConstraints forces an infinite width".
          //
          // Solution: wrap every button in Expanded so the Row divides the
          // available finite width equally among the three buttons.
          // SizedBox gaps replace spaceBetween spacing.
          Row(
            children: [
              // APPROVE
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    // FIX (null crash): use literal Color values — never
                    // MaterialColor.shade* accessors inside styleFrom, as
                    // those can be null before the theme is fully resolved.
                    backgroundColor: const Color(0xFF4CAF50), // green
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _updateKycStatus(
                    uid: uid,
                    verified: true,
                    status: 'approved',
                    context: context,
                  ),
                  child: const Text('Approve'),
                ),
              ),

              const SizedBox(width: 8),

              // SUSPEND
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF44336), // red
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _updateKycStatus(
                    uid: uid,
                    verified: false,
                    status: 'suspended',
                    context: context,
                  ),
                  child: const Text('Suspend'),
                ),
              ),

              const SizedBox(width: 8),

              // DETAILS
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    // FIX (null crash): literal color instead of
                    // Colors.blue.shade50 which can be null at build time
                    backgroundColor: const Color(0xFFE3F2FD),
                    foregroundColor: const Color(0xFF1565C0),
                  ),
                  onPressed: () {
                    // TODO: Navigate to traveler details screen
                  },
                  child: const Text('Details'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),

      appBar: AppBar(
        title: const Text('Traveler Management'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),

      // Outer Column + Expanded gives the StreamBuilder a finite height so
      // the inner Expanded → ListView has a bounded constraint to fill.
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'traveler')
                  .snapshots(),
              builder: (context, snapshot) {
                // ---- Error ----
                if (snapshot.hasError) {
                  if (kDebugMode) {
                    debugPrint(
                        'TravelerManagement error: ${snapshot.error}\n'
                        '${snapshot.stackTrace}');
                  }
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to load travelers.\nPlease try again later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  );
                }

                // ---- Loading ----
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (kDebugMode) {
                  debugPrint(
                    'TravelerManagement snapshot received — '
                    'docs: ${snapshot.data?.docs.length ?? 0}, '
                    'fromCache: ${snapshot.data?.metadata.isFromCache}',
                  );
                }

                // ---- Empty ----
                final List<QueryDocumentSnapshot> travelers =
                    snapshot.data?.docs ?? [];

                if (travelers.isEmpty) {
                  return const Center(child: Text('No travelers found'));
                }

                // ---- Compute stats ----
                int active = 0;
                int pending = 0;

                for (final doc in travelers) {
                  final Map<String, dynamic> d =
                      (doc.data() as Map<String, dynamic>?) ?? {};
                  if (d['kycVerified'] == true) active++;
                  if (d['kycStatus'] == 'submitted') pending++;
                }

                // ---- Data ----
                return Column(
                  children: [
                    // STAT CARDS
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // 3 cards + 2 × 8 px gaps = 16 px total gap
                          final double cardWidth =
                              (constraints.maxWidth - 16) / 3;
                          return Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              _statCard(
                                active.toString(), 'Active',
                                const Color(0xFFE8F5E9), // green.shade50
                                const Color(0xFF4CAF50), // green
                                width: cardWidth,
                              ),
                              _statCard(
                                pending.toString(), 'Pending',
                                const Color(0xFFFFF3E0), // orange.shade50
                                const Color(0xFFFF9800), // orange
                                width: cardWidth,
                              ),
                              _statCard(
                                travelers.length.toString(), 'Total',
                                const Color(0xFFE3F2FD), // blue.shade50
                                const Color(0xFF2196F3), // blue
                                width: cardWidth,
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    const Divider(height: 1),

                    // TRAVELER LIST
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: travelers.length,
                        itemBuilder: (context, index) {
                          final doc = travelers[index];
                          return KeyedSubtree(
                            key: ValueKey(doc.id),
                            child: _travelerCard(context, doc),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}