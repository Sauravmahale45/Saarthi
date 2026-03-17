import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../features/tracking/parcel_tracking_screen.dart';

// Color palette
const _indigo = Color(0xFF4F46E5);
const _indigoL = Color(0xFF818CF8);
const _teal = Color(0xFF14B8A6);
const _orange = Color(0xFFF97316);
const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);
const _bg = Color(0xFFF5F7FF);
const _card = Colors.white;
const _text1 = Color(0xFF0F172A);
const _text2 = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);

class ParcelManagementScreen extends StatefulWidget {
  const ParcelManagementScreen({super.key});

  @override
  State<ParcelManagementScreen> createState() => _ParcelManagementScreenState();
}

class _ParcelManagementScreenState extends State<ParcelManagementScreen> {
  String _searchText = '';
  String? _selectedStatusFilter;
  final TextEditingController _searchController = TextEditingController();

  Stream<QuerySnapshot> _parcelsStream() {
    return FirebaseFirestore.instance
        .collection('parcels')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Safely extracts all fields from a parcel document.
  Map<String, dynamic> _safeParcel(QueryDocumentSnapshot doc) {
    final Map<String, dynamic> raw =
        (doc.data() as Map<String, dynamic>?) ?? {};

    // Helper to safely get a string; if missing, fallback to doc.id for orderId
    String safeString(String key, [String fallback = 'N/A']) {
      final val = raw[key];
      return val is String && val.isNotEmpty ? val : fallback;
    }

    // Special handling for orderId: if missing, use document id
    final orderId = safeString('orderId');
    final displayOrderId = orderId == 'N/A' ? doc.id : orderId;

    // Helper to safely get a number as double
    double safeDouble(String key, [double fallback = 0.0]) {
      final val = raw[key];
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? fallback;
      return fallback;
    }

    // Helper to safely get a map
    Map<String, dynamic> safeMap(String key) {
      final val = raw[key];
      return val is Map<String, dynamic> ? val : {};
    }

    // Parse pickup and drop maps
    final pickupMap = safeMap('pickup');
    final dropMap = safeMap('drop');

    return {
      'id': doc.id,
      'orderId': displayOrderId,
      'category': safeString('category'),
      'subCategory': safeString('subCategory'),
      'size': safeString('size'),
      'weight': safeDouble('weight'),
      'price': safeDouble('price'),
      'distanceKm': safeDouble('distanceKm'),
      'etaMinutes': safeDouble('etaMinutes'),
      'status': safeString('status', 'Pending'),
      'description': safeString('description'),
      'photoUrl': safeString('photoUrl'),
      'senderId': safeString('senderId'),
      'senderName': safeString('senderName'),
      'senderEmail': safeString('senderEmail'),
      'receiverName': safeString('receiverName'),
      'receiverPhone': safeString('receiverPhone'),
      'travelerId': safeString('travelerId'),
      'travelerName': safeString('travelerName'),
      'fromCity': safeString('fromCity'),
      'toCity': safeString('toCity'),
      'paymentStatus': safeString('paymentStatus'),
      'paymentId': safeString('paymentId'),
      'pickupOTP': raw['pickupOTP'], // can be null
      'pickupOTPAttempts': raw['pickupOTPAttempts'] ?? 0,
      'pickupStarted': raw['pickupStarted'] ?? false,
      'createdAt': raw['createdAt'] as Timestamp?,
      'acceptedAt': raw['acceptedAt'] as Timestamp?,
      'pickedAt': raw['pickedAt'] as Timestamp?,
      'deliveryDeadline': raw['deliveryDeadline'] as Timestamp?,
      'paidAt': raw['paidAt'] as Timestamp?,
      'pickup': pickupMap,
      'drop': dropMap,
    };
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return 'N/A';
    return DateFormat.yMMMd().add_jm().format(ts.toDate());
  }

  String _formatWeight(double weight) {
    return weight.toStringAsFixed(1);
  }

  // ---------------------------------------------------------------------------
  // BOTTOM DRAWER FOR DETAILS
  // ---------------------------------------------------------------------------
  void _showParcelDetails(Map<String, dynamic> parcel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: _card,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Parcel Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _indigo,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        _detailSection('Order Information', [
                          _detailRow('Order ID', parcel['orderId']),
                          _detailRow(
                            'Status',
                            parcel['status'],
                            valueColor: _statusColor(parcel['status']),
                          ),
                          _detailRow('Category', parcel['category']),
                          _detailRow('Sub‑Category', parcel['subCategory']),
                          _detailRow('Size', parcel['size']),
                          _detailRow(
                            'Weight',
                            '${_formatWeight(parcel['weight'])} kg',
                          ),
                          _detailRow(
                            'Price',
                            '₹${parcel['price'].toStringAsFixed(2)}',
                          ),
                          _detailRow(
                            'Distance',
                            '${parcel['distanceKm'].toStringAsFixed(1)} km',
                          ),
                          _detailRow('ETA', '${parcel['etaMinutes']} min'),
                        ]),
                        _detailSection('Sender', [
                          _detailRow('Name', parcel['senderName']),
                          _detailRow('Email', parcel['senderEmail']),
                        ]),
                        _detailSection('Receiver', [
                          _detailRow('Name', parcel['receiverName']),
                          _detailRow('Phone', parcel['receiverPhone']),
                        ]),
                        _detailSection('Pickup', [
                          _detailRow(
                            'Address',
                            parcel['pickup']['address'] ?? 'N/A',
                          ),
                          _detailRow('Area', parcel['pickup']['area'] ?? 'N/A'),
                          _detailRow('City', parcel['pickup']['city'] ?? 'N/A'),
                          if (parcel['pickupOTP'] != null)
                            _detailRow('OTP', parcel['pickupOTP'].toString()),
                          _detailRow(
                            'OTP Attempts',
                            parcel['pickupOTPAttempts'].toString(),
                          ),
                          _detailRow(
                            'Pickup Started',
                            parcel['pickupStarted'] ? 'Yes' : 'No',
                          ),
                        ]),
                        _detailSection('Drop', [
                          _detailRow(
                            'Address',
                            parcel['drop']['address'] ?? 'N/A',
                          ),
                          _detailRow('Area', parcel['drop']['area'] ?? 'N/A'),
                          _detailRow('City', parcel['drop']['city'] ?? 'N/A'),
                        ]),
                        _detailSection('Traveler', [
                          _detailRow('Name', parcel['travelerName']),
                          _detailRow('ID', parcel['travelerId']),
                        ]),
                        _detailSection('Timestamps', [
                          _detailRow(
                            'Created',
                            _formatDate(parcel['createdAt']),
                          ),
                          _detailRow(
                            'Accepted',
                            _formatDate(parcel['acceptedAt']),
                          ),
                          _detailRow('Picked', _formatDate(parcel['pickedAt'])),
                          _detailRow(
                            'Deadline',
                            _formatDate(parcel['deliveryDeadline']),
                          ),
                          _detailRow('Paid', _formatDate(parcel['paidAt'])),
                        ]),
                        _detailSection('Payment', [
                          _detailRow('Status', parcel['paymentStatus']),
                          _detailRow('Payment ID', parcel['paymentId']),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _indigo,
            ),
          ),
        ),
        ...rows,
        const Divider(height: 24, color: _border),
      ],
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 13, color: _text2)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? _text1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Delivered':
        return _green;
      case 'picked':
      case 'In Transit':
        return _teal;
      case 'Pending':
        return _orange;
      case 'Cancelled':
        return _red;
      default:
        return _text2;
    }
  }

  // ---------------------------------------------------------------------------
  // CARD WIDGET (modern, full‑width)
  // ---------------------------------------------------------------------------
  Widget _parcelCard(BuildContext context, Map<String, dynamic> parcel) {
    final status = parcel['status'] as String;
    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            color: Colors.black.withOpacity(0.02),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _indigoL.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.inventory_2_outlined, color: _indigo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            parcel['orderId'],
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _text1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${parcel['fromCity']} → ${parcel['toCity']}',
                      style: TextStyle(fontSize: 12, color: _text2),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person_outline, size: 12, color: _text2),
                        const SizedBox(width: 4),
                        Text(
                          parcel['senderName'],
                          style: TextStyle(fontSize: 12, color: _text1),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.star, size: 12, color: _orange),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatWeight(parcel['weight'])} kg',
                          style: TextStyle(fontSize: 12, color: _text2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: _border),
          // Two action buttons (no cancel)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.info_outline, size: 14, color: _indigo),
                  label: Text(
                    'Details',
                    style: TextStyle(fontSize: 11, color: _indigo),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigoL.withOpacity(0.1),
                    foregroundColor: _indigo,
                    minimumSize: const Size(double.infinity, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: _indigoL.withOpacity(0.3)),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _showParcelDetails(parcel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(
                    Icons.track_changes,
                    size: 14,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Track',
                    style: TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigo,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    // Navigate to ParcelTrackingScreen with required data
                    final drop = parcel['drop'] as Map<String, dynamic>;
                    final travelerName = parcel['travelerName'] ?? 'Traveler';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ParcelTrackingScreen(
                          parcelId: parcel['id'],
                          destLat: (drop['lat'] as num?)?.toDouble() ?? 0.0,
                          destLng: (drop['lng'] as num?)?.toDouble() ?? 0.0,
                          destLabel: drop['city'] ?? 'Destination',
                          travelerName: travelerName,
                        ),
                      ),
                    );
                  },
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        title: const Text(
          'Parcel Management',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.notifications_none, size: 20),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _parcelsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: _red, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to load parcels.\nPlease try again later.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _text2, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          final List<Map<String, dynamic>> allParcels = allDocs
              .map(_safeParcel)
              .toList();

          // Extract unique statuses for filter
          final statuses = allParcels
              .map((p) => p['status'] as String)
              .toSet()
              .toList();

          // Filter by status and search (search by orderId, sender, etc.)
          final filteredParcels = allParcels.where((p) {
            final matchesStatus =
                _selectedStatusFilter == null ||
                p['status'] == _selectedStatusFilter;
            final searchLower = _searchText.toLowerCase();
            final matchesSearch =
                _searchText.isEmpty ||
                (p['orderId'] as String).toLowerCase().contains(searchLower) ||
                (p['senderName'] as String).toLowerCase().contains(
                  searchLower,
                ) ||
                (p['travelerName'] as String).toLowerCase().contains(
                  searchLower,
                );
            return matchesStatus && matchesSearch;
          }).toList();

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchText = value),
                  decoration: InputDecoration(
                    hintText: 'Search by order, sender, traveler...',
                    hintStyle: TextStyle(fontSize: 14, color: _text2),
                    prefixIcon: Icon(Icons.search, size: 18, color: _indigo),
                    filled: true,
                    fillColor: _card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide(color: _indigo, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              // Status filter chips
              if (statuses.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: Text(
                            'All',
                            style: TextStyle(fontSize: 12, color: _text1),
                          ),
                          selected: _selectedStatusFilter == null,
                          onSelected: (_) =>
                              setState(() => _selectedStatusFilter = null),
                          backgroundColor: _card,
                          selectedColor: _indigo.withOpacity(0.2),
                          checkmarkColor: _indigo,
                          shape: StadiumBorder(
                            side: BorderSide(color: _border),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ...statuses.map((status) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(
                                status,
                                style: TextStyle(fontSize: 12, color: _text1),
                              ),
                              selected: _selectedStatusFilter == status,
                              onSelected: (_) => setState(
                                () => _selectedStatusFilter = status,
                              ),
                              backgroundColor: _card,
                              selectedColor: _indigo.withOpacity(0.2),
                              checkmarkColor: _indigo,
                              shape: StadiumBorder(
                                side: BorderSide(color: _border),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              // Parcel list
              Expanded(
                child: filteredParcels.isEmpty
                    ? Center(
                        child: Text(
                          'No parcels found',
                          style: TextStyle(fontSize: 14, color: _text2),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: filteredParcels.length,
                        itemBuilder: (context, index) {
                          final parcel = filteredParcels[index];
                          return KeyedSubtree(
                            key: ValueKey(parcel['id']),
                            child: _parcelCard(context, parcel),
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
