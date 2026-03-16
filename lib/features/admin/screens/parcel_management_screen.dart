import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ParcelManagementScreen extends StatelessWidget {
  const ParcelManagementScreen({super.key});

  // ---------------------------------------------------------------------------
  // FIRESTORE STREAM
  // Real-time stream of the entire 'parcels' collection ordered by creation
  // date (newest first).  Falls back gracefully if the field is absent.
  // ---------------------------------------------------------------------------

  Stream<QuerySnapshot> _parcelsStream() {
    return FirebaseFirestore.instance
        .collection('parcels')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ---------------------------------------------------------------------------
  // SAFE DATA EXTRACTION
  // All field access is done through this helper so no single missing field
  // can crash the UI.
  // ---------------------------------------------------------------------------

  Map<String, String> _safeParcel(QueryDocumentSnapshot doc) {
    final Map<String, dynamic> raw =
        (doc.data() as Map<String, dynamic>?) ?? {};

    return {
      'id':       raw['id']       is String ? raw['id']       as String : doc.id,
      'sender':   raw['sender']   is String ? raw['sender']   as String : 'Unknown',
      'traveler': raw['traveler'] is String ? raw['traveler'] as String : 'Unassigned',
      'weight':   raw['weight']   is String ? raw['weight']   as String : 'N/A',
      'status':   raw['status']   is String ? raw['status']   as String : 'Pending',
    };
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),

      appBar: AppBar(
        title: const Text('Parcel Monitoring'),
        backgroundColor: const Color(0xFF2D3E91),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: hook up a search delegate
            },
          ),
        ],
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: _parcelsStream(),
        builder: (context, snapshot) {

          // ---- Error ----
          if (snapshot.hasError) {
            if (kDebugMode) {
              debugPrint('ParcelManagement error: ${snapshot.error}');
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load parcels.\nPlease try again later.',
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

          // ---- Parse docs safely ----
          final List<QueryDocumentSnapshot> rawDocs =
              snapshot.data?.docs ?? [];

          if (kDebugMode) {
            debugPrint('ParcelManagement: ${rawDocs.length} docs received');
          }

          // Extract safe maps once — reused for both stats and cards.
          final List<Map<String, String>> parcels =
              rawDocs.map(_safeParcel).toList();

          // ---- Live stats (requirement 5) ----
          final int total     = parcels.length;
          final int pending   = parcels.where((p) => p['status'] == 'Pending').length;
          final int inTransit = parcels.where((p) => p['status'] == 'In Transit').length;
          final int delivered = parcels.where((p) => p['status'] == 'Delivered').length;

          return Column(
            children: [

              // ---- STATS BANNER ----
              Container(
                color: const Color(0xFF2D3E91),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Divide available width evenly among 4 cards with 3 gaps
                    final double cardWidth =
                        (constraints.maxWidth - 24) / 4;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _statCard(total.toString(),     'Total',      cardWidth),
                        _statCard(pending.toString(),   'Pending',    cardWidth),
                        _statCard(inTransit.toString(), 'In Transit', cardWidth),
                        _statCard(delivered.toString(), 'Delivered',  cardWidth),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              // ---- SECTION HEADER ----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'All Parcels',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3E91),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EAF6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.filter_list,
                              size: 16, color: Color(0xFF2D3E91)),
                          SizedBox(width: 4),
                          Text(
                            'Filter',
                            style: TextStyle(
                              color: Color(0xFF2D3E91),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ---- EMPTY STATE ----
              if (parcels.isEmpty)
                const Expanded(
                  child: Center(child: Text('No parcels found')),
                )

              // ---- PARCEL LIST ----
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: parcels.length,
                    itemBuilder: (context, index) {
                      // Use Firestore doc id as stable key so Flutter diffs
                      // the list correctly on real-time updates.
                      return KeyedSubtree(
                        key: ValueKey(rawDocs[index].id),
                        child: _parcelCard(context, parcels[index]),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PARCEL CARD
  // ---------------------------------------------------------------------------

  Widget _parcelCard(BuildContext context, Map<String, String> parcel) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Color(0x1A2D3E91),
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ---- CARD HEADER: parcel ID + status chip ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EAF6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFF2D3E91),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parcel['id']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const Text(
                        'Live from Firestore',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              _statusChip(parcel['status']!),
            ],
          ),

          const Divider(height: 20),

          // ---- DETAILS ROW ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _detailColumn('Sender',   parcel['sender']!),
              _detailColumn('Traveler', parcel['traveler']!),
              _detailColumn('Weight',   parcel['weight']!),
            ],
          ),

          const SizedBox(height: 14),

          // ---- ACTION BUTTONS ----
          // FIX: Expanded buttons prevent infinite-width constraint crashes
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8EAF6),
                    foregroundColor: const Color(0xFF2D3E91),
                  ),
                  onPressed: () {
                    // TODO: Navigate to parcel detail screen
                  },
                  child: const Text('View Details'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D3E91),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // TODO: Navigate to tracking screen
                  },
                  child: const Text('Track'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFDECEA),
                    foregroundColor: Colors.red,
                  ),
                  onPressed: () => _confirmCancel(context, parcel['id']!),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CANCEL CONFIRMATION
  // ---------------------------------------------------------------------------

  Future<void> _confirmCancel(BuildContext context, String parcelId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Parcel'),
        content: Text('Cancel parcel "$parcelId"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Parcel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Update status to Cancelled in Firestore; delete if preferred
      await FirebaseFirestore.instance
          .collection('parcels')
          .where('id', isEqualTo: parcelId)
          .limit(1)
          .get()
          .then((snap) {
        for (final doc in snap.docs) {
          doc.reference.update({'status': 'Cancelled'});
        }
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not cancel parcel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // REUSABLE HELPER WIDGETS
  // ---------------------------------------------------------------------------

  Widget _statusChip(String status) {
    // FIX: literal Color values — no .shade accessor that can be null
    final Color bg;
    final Color text;

    switch (status) {
      case 'Delivered':
        bg   = const Color(0xFFE8F5E9); // green.shade50
        text = const Color(0xFF4CAF50); // green
        break;
      case 'Pending':
        bg   = const Color(0xFFFFF3E0); // orange.shade50
        text = const Color(0xFFFF9800); // orange
        break;
      case 'Cancelled':
        bg   = const Color(0xFFFFEBEE); // red.shade50
        text = const Color(0xFFF44336); // red
        break;
      default: // In Transit
        bg   = const Color(0xFFFFE0B2); // orange.shade100
        text = const Color(0xFFE64A19); // deepOrange
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _detailColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _statCard(String number, String label, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white24,
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
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}