// lib/screens/available_traveler.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class AvailableTravelerScreen extends StatefulWidget {
  final String parcelId;
  const AvailableTravelerScreen({super.key, required this.parcelId});

  @override
  State<AvailableTravelerScreen> createState() =>
      _AvailableTravelerScreenState();
}

class _AvailableTravelerScreenState extends State<AvailableTravelerScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _parcelData;
  List<QueryDocumentSnapshot> _travelers = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch parcel details
      final parcelDoc = await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .get();
      if (!parcelDoc.exists) {
        setState(() {
          _error = 'Parcel not found';
          _isLoading = false;
        });
        return;
      }
      final parcel = parcelDoc.data()!;
      final fromCity = parcel['fromCity'] as String;
      final toCity = parcel['toCity'] as String;
      final createdAt = (parcel['createdAt'] as Timestamp).toDate();
      final deadline = (parcel['deliveryDeadline'] as Timestamp).toDate();

      // 2. Query travelRoutes matching cities and travel date between createdAt and deadline
      final travelSnapshot = await FirebaseFirestore.instance
          .collection('travelRoutes')
          .where('fromCity', isEqualTo: fromCity)
          .where('toCity', isEqualTo: toCity)
          .where(
            'travelDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(createdAt),
          )
          .where(
            'travelDate',
            isLessThanOrEqualTo: Timestamp.fromDate(deadline),
          )
          .where('status', isEqualTo: 'active') // only active travelers
          .get();

      // 3. Optionally filter out travelers who already have an assigned parcel
      //    (assuming each traveler can carry only one parcel per route)
      final available = travelSnapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        // If traveler already has an assigned parcel ID, skip
        return data['assignedParcelId'] == null;
      }).toList();

      setState(() {
        _travelers = available;
        _parcelData = parcel;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _assignTraveler(
    String travelerId,
    String travelerName,
    String routeId,
  ) async {
    try {
      // Update parcel with traveler info
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({
            'travelerId': travelerId,
            'travelerName': travelerName,
            'status': 'assigned', // or 'matched'
            'assignedAt': FieldValue.serverTimestamp(),
          });

      // Update travelRoute to mark as assigned (optional)
      await FirebaseFirestore.instance
          .collection('travelRoutes')
          .doc(routeId)
          .update({
            'assignedParcelId': widget.parcelId,
            'status': 'booked', // or change status to indicate it's taken
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Traveler assigned successfully!'),
            backgroundColor: Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Navigate to sender dashboard or confirmation screen
        context.go('/sender');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error assigning traveler: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => context.go('/sender'),
        ),
        title: const Text(
          'Available Travelers',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error: $_error',
                    style: const TextStyle(color: Color(0xFFEF4444)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _travelers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_search_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No travelers found for this route',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try adjusting your delivery deadline',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go('/sender'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Back to Dashboard'),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Parcel summary card
                  if (_parcelData != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              color: Color(0xFFFF6B35),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_parcelData!['fromCity']} → ${_parcelData!['toCity']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Deadline: ${_formatDate((_parcelData!['deliveryDeadline'] as Timestamp).toDate())}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF888888),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '₹${_parcelData!['price']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF6B35),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Text(
                    'Select a traveler',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _travelers.length,
                      itemBuilder: (context, index) {
                        final traveler =
                            _travelers[index].data() as Map<String, dynamic>;
                        final routeId = _travelers[index].id;
                        final travelDate = (traveler['travelDate'] as Timestamp)
                            .toDate();
                        return _TravelerCard(
                          name: traveler['travelerName'] ?? 'Unknown',
                          fromCity: traveler['fromCity'],
                          toCity: traveler['toCity'],
                          travelDate: travelDate,
                          onSelect: () => _assignTraveler(
                            traveler['travelerId'],
                            traveler['travelerName'] ?? 'Traveler',
                            routeId,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TravelerCard extends StatelessWidget {
  final String name;
  final String fromCity;
  final String toCity;
  final DateTime travelDate;
  final VoidCallback onSelect;

  const _TravelerCard({
    required this.name,
    required this.fromCity,
    required this.toCity,
    required this.travelDate,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFFF6B35).withOpacity(0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'T',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6B35),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$fromCity → $toCity',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('dd MMM yyyy').format(travelDate),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSelect,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Select Traveler'),
            ),
          ),
        ],
      ),
    );
  }
}
