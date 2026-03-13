import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// ── Brand colours (same as app) ───────────────────────────────────────────────
const _indigo = Color(0xFF4F46E5);
const _teal = Color(0xFF14B8A6);
const _orange = Color(0xFFF97316);
const _bg = Color(0xFFF5F7FF);
const _text1 = Color(0xFF0F172A);
const _text2 = Color(0xFF64748B);
const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);
const _card = Colors.white;

class ParcelDetailsScreen extends StatefulWidget {
  final String parcelId;
  const ParcelDetailsScreen({super.key, required this.parcelId});

  @override
  State<ParcelDetailsScreen> createState() => _ParcelDetailsScreenState();
}

class _ParcelDetailsScreenState extends State<ParcelDetailsScreen> {
  Map<String, dynamic>? _parcel;
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _traveler;
  bool _loadingTraveler = false;
  String? _previousTravelerId;

  StreamSubscription<DocumentSnapshot>? _parcelSubscription;

  @override
  void initState() {
    super.initState();
    _setupParcelListener();
  }

  void _setupParcelListener() {
    _parcelSubscription = FirebaseFirestore.instance
        .collection('parcels')
        .doc(widget.parcelId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!snapshot.exists) {
              setState(() {
                _error = 'Parcel not found.';
                _loading = false;
              });
              return;
            }

            final data = snapshot.data()!;
            setState(() {
              _parcel = data;
              _loading = false;
            });

            final travelerId = data['travelerId'] as String?;
            final status = data['status'] as String?;
            if (travelerId != null &&
                (status == 'requested' || status == 'accepted')) {
              if (travelerId != _previousTravelerId) {
                _previousTravelerId = travelerId;
                _fetchTraveler(travelerId);
              }
            } else {
              // Clear traveler if not needed
              setState(() => _traveler = null);
            }
          },
          onError: (error) {
            setState(() {
              _error = error.toString();
              _loading = false;
            });
          },
        );
  }

  Future<void> _fetchTraveler(String travelerId) async {
    setState(() => _loadingTraveler = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(travelerId)
          .get();
      if (doc.exists) {
        setState(() => _traveler = doc.data());
      }
    } catch (e) {
      debugPrint('Error fetching traveler: $e');
    } finally {
      setState(() => _loadingTraveler = false);
    }
  }

  @override
  void dispose() {
    _parcelSubscription?.cancel();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _indigo,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Parcel Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _indigo))
          : _error != null
          ? _ErrorView(error: _error!)
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final p = _parcel!;
    final status = p['status'] as String? ?? 'pending';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: p['photoUrl'] != null && p['photoUrl'].toString().isNotEmpty
                ? Image.network(
                    p['photoUrl'],
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(),
                  )
                : _imagePlaceholder(),
          ),
          const SizedBox(height: 16),

          // Status row
          Row(
            children: [
              _buildStatusChip(status),
              const Spacer(),
              if (p['createdAt'] != null)
                Text(
                  'Posted ${_formatDate(p['createdAt'])}',
                  style: const TextStyle(fontSize: 12, color: _text2),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Route
          Row(
            children: [
              Expanded(
                child: _RouteBox(city: p['fromCity'] ?? '?', label: 'From'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: _teal,
                  size: 20,
                ),
              ),
              Expanded(
                child: _RouteBox(city: p['toCity'] ?? '?', label: 'To'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Category & price card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _categoryIcon(p['category']),
                    color: _indigo,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['category'] ?? 'Parcel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _text1,
                        ),
                      ),
                      if (p['subCategory'] != null)
                        Text(
                          p['subCategory'],
                          style: const TextStyle(fontSize: 13, color: _text2),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Price',
                        style: TextStyle(fontSize: 10, color: _text2),
                      ),
                      Text(
                        '₹${p['price'] ?? 0}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Parcel details card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Parcel Details',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _text1,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SpecItem(
                      icon: Icons.scale_outlined,
                      label: 'Weight',
                      value: '${p['weight'] ?? 0} kg',
                    ),
                    _SpecItem(
                      icon: Icons.straighten_outlined,
                      label: 'Size',
                      value: p['size'] ?? '—',
                    ),
                    _SpecItem(
                      icon: Icons.inventory_2_outlined,
                      label: 'Category',
                      value: p['category'] ?? '—',
                    ),
                  ],
                ),
                if (p['description'] != null &&
                    p['description'].toString().isNotEmpty) ...[
                  const Divider(color: Color(0xFFF1F5F9), height: 24),
                  Text(
                    p['description'],
                    style: const TextStyle(fontSize: 13, color: _text2),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Contact info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _ContactTile(
                  icon: Icons.person_outline,
                  label: 'Receiver',
                  name: p['receiverName'] ?? '',
                  phone: p['receiverPhone'] ?? '',
                ),
                const Divider(color: Color(0xFFF1F5F9), height: 20),
                _ContactTile(
                  icon: Icons.send_outlined,
                  label: 'Sender',
                  name: p['senderName'] ?? '',
                  email: p['senderEmail'] ?? '',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Conditional footer based on status
          if (status == 'pending')
            _buildPendingFooter()
          else if (status == 'requested' || status == 'accepted')
            Column(
              children: [
                _buildTravelerFooter(status),
                if (p['pickupStarted'] == true && p['pickupOTP'] != null)
                  _buildPickupOTPSection(p),
              ],
            )
          else if (status == 'picked')
            _buildPickedFooter()
          else if (status == 'delivered')
            _buildDeliveredBadge(),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 50,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String label;
    IconData icon;
    switch (status) {
      case 'pending':
        color = _orange;
        label = 'Pending';
        icon = Icons.hourglass_empty_rounded;
        break;
      case 'requested':
        color = _teal;
        label = 'Request Sent';
        icon = Icons.pending_actions_rounded;
        break;
      case 'accepted':
        color = _green;
        label = 'Accepted';
        icon = Icons.check_circle_rounded;
        break;
      case 'picked':
        color = _indigo;
        label = 'Picked Up';
        icon = Icons.local_shipping_rounded;
        break;
      case 'delivered':
        color = _green;
        label = 'Delivered';
        icon = Icons.check_circle_rounded;
        break;
      default:
        color = _text2;
        label = status;
        icon = Icons.help_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingFooter() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          context.push('/available-traveler/${widget.parcelId}');
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 20),
            SizedBox(width: 8),
            Text(
              'Find Travelers',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTravelerFooter(String status) {
    if (_loadingTraveler) {
      return const Center(child: CircularProgressIndicator(color: _indigo));
    }
    if (_traveler == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _orange.withOpacity(0.3)),
        ),
        child: const Text(
          'Traveler details not available',
          style: TextStyle(color: _orange),
        ),
      );
    }

    final traveler = _traveler!;
    final isAccepted = status == 'accepted';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAccepted ? _green.withOpacity(0.04) : _teal.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAccepted ? _green.withOpacity(0.3) : _teal.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isAccepted
                      ? _green.withOpacity(0.1)
                      : _teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isAccepted
                      ? Icons.check_circle_rounded
                      : Icons.pending_actions_rounded,
                  color: isAccepted ? _green : _teal,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAccepted ? 'Assigned Traveler' : 'Requested Traveler',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _text1,
                      ),
                    ),
                    Text(
                      traveler['name'] ?? traveler['displayName'] ?? 'Traveler',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: traveler['email'] ?? '—',
          ),
          if (traveler['phone'] != null)
            _InfoRow(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: traveler['phone'],
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: isAccepted ? _green : _teal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAccepted
                        ? 'This traveler has accepted your parcel. Contact them to arrange pickup.'
                        : 'Waiting for the traveler to accept your request.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isAccepted ? _green : _teal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// New widget: OTP display section shown when pickup has started.
  Widget _buildPickupOTPSection(Map<String, dynamic> parcel) {
    final otp = parcel['pickupOTP'] as String? ?? 'N/A';
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _teal.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'Pickup Verification',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _text1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Share this OTP with the traveler when they arrive to collect the parcel.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _text2),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: _indigo.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _indigo.withOpacity(0.2)),
            ),
            child: Text(
              otp,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: _indigo,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'This OTP confirms parcel pickup.',
            style: TextStyle(fontSize: 12, color: _text2),
          ),
        ],
      ),
    );
  }

  Widget _buildPickedFooter() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          context.push('/make-payment/${widget.parcelId}');
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payment_rounded, size: 20),
            SizedBox(width: 8),
            Text(
              'Make Payment',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveredBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, color: _green, size: 24),
          SizedBox(width: 8),
          Text(
            'Parcel Delivered',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _green,
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'document':
        return Icons.description_outlined;
      case 'food':
        return Icons.fastfood_outlined;
      case 'electronics':
        return Icons.phone_android_outlined;
      case 'clothing':
        return Icons.checkroom_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else {
      return DateFormat('dd MMM').format(dt);
    }
  }
}

// ── Helper widgets (unchanged) ──────────────────────────────────────────────
class _RouteBox extends StatelessWidget {
  final String city;
  final String label;
  const _RouteBox({required this.city, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: _indigo.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _indigo.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: _text2)),
          const SizedBox(height: 2),
          Text(
            city,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _indigo,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecItem extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _SpecItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: _text2),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _text1,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 10, color: _text2)),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String label, name, phone, email;
  const _ContactTile({
    required this.icon,
    required this.label,
    required this.name,
    this.phone = '',
    this.email = '',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _indigo.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _indigo, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: _text2)),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _text1,
                ),
              ),
              if (phone.isNotEmpty)
                Text(
                  phone,
                  style: const TextStyle(fontSize: 12, color: _text2),
                ),
              if (email.isNotEmpty)
                Text(
                  email,
                  style: const TextStyle(fontSize: 12, color: _text2),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _text2),
          const SizedBox(width: 8),
          Text('$label:', style: const TextStyle(fontSize: 12, color: _text2)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _text1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
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
              onPressed: () => Navigator.pop(context),
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
}
