import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'pickup_otp_verify_screen.dart'; // <-- import the OTP screen

// 👇 NEW: import tracking services
import '../../tracking/permission_service.dart';
import '../../tracking/tracking_service.dart';

// ── Brand colours ─────────────────────────────────────────────────────────────
const _indigo = Color(0xFF4F46E5);
const _teal = Color(0xFF14B8A6);
const _orange = Color(0xFFF97316);
const _bg = Color(0xFFF5F7FF);
const _text1 = Color(0xFF0F172A);
const _text2 = Color(0xFF64748B);
const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);
const _card = Colors.white;

class TravelerParcelDetailsScreen extends StatefulWidget {
  final String parcelId;
  const TravelerParcelDetailsScreen({super.key, required this.parcelId});

  @override
  State<TravelerParcelDetailsScreen> createState() =>
      _TravelerParcelDetailsScreenState();
}

class _TravelerParcelDetailsScreenState
    extends State<TravelerParcelDetailsScreen> {
  Map<String, dynamic>? _parcel;
  bool _loading = true;
  String? _error;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _loadParcel();
  }

  // 👇 NEW: dispose method to stop tracking when screen is destroyed
  @override
  void dispose() {
    TrackingService.instance.stopTracking();
    super.dispose();
  }

  Future<void> _loadParcel() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .get();

      if (!doc.exists) {
        setState(() {
          _error = 'Parcel not found.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _parcel = doc.data();
        _loading = false;
      });

      // 👇 NEW: if parcel is already picked, start tracking automatically
      if (_parcel?['status'] == 'picked') {
        _startTrackingIfPicked();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // 👇 NEW: method to request permissions and start tracking
  Future<void> _startTrackingIfPicked() async {
    final ready = await PermissionService.ensureLocationReady(context);
    if (!ready) {
      _showToast(
        'Cannot start tracking without location access',
        isError: true,
      );
      return;
    }
    await TrackingService.instance.startTracking(widget.parcelId);
    debugPrint('Tracking started for parcel ${widget.parcelId}');
  }

  String _generateOTP() {
    final rand = Random();
    return (1000 + rand.nextInt(9000)).toString();
  }

  Future<void> _acceptParcel() async {
    setState(() => _updating = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({'status': 'accepted', 'travelerId': uid});
      setState(() {
        _parcel!['status'] = 'accepted';
        _parcel!['travelerId'] = uid;
        _updating = false;
      });
      _showToast('✅ Parcel accepted!');
    } catch (e) {
      setState(() => _updating = false);
      _showToast('Failed to accept: $e', isError: true);
    }
  }

  Future<void> _rejectParcel() async {
    setState(() => _updating = true);
    try {
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({'status': 'pending', 'travelerId': null});
      setState(() => _updating = false);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _updating = false);
      _showToast('Failed to reject: $e', isError: true);
    }
  }

  /// Generates OTP, stores it in Firestore, then navigates to OTP screen.
  Future<void> _startPickup() async {
    setState(() => _updating = true);
    try {
      final otp = _generateOTP();
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({'pickupOTP': otp, 'pickupStarted': true});

      setState(() {
        _parcel!['pickupOTP'] = otp;
        _parcel!['pickupStarted'] = true;
        _updating = false;
      });

      if (!mounted) return;

      // Slide-up navigation to OTP verify screen
      final verified = await Navigator.of(context).push<bool>(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) =>
              PickupOTPVerifyScreen(parcelId: widget.parcelId),
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 480),
        ),
      );

      // Reload parcel if OTP was verified successfully
      if (verified == true && mounted) {
        await _loadParcel(); // This will trigger tracking if status becomes 'picked'
      }
    } catch (e) {
      setState(() => _updating = false);
      _showToast('Failed to start pickup: $e', isError: true);
    }
  }

  Future<void> _markAsDelivered() async {
    setState(() => _updating = true);
    try {
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({
            'status': 'delivered',
            'deliveredAt': FieldValue.serverTimestamp(),
          });

      // 👇 NEW: stop tracking because parcel is delivered
      await TrackingService.instance.stopTracking();

      setState(() {
        _parcel!['status'] = 'delivered';
        _updating = false;
      });
      _showToast('✅ Parcel marked as delivered!');
    } catch (e) {
      setState(() => _updating = false);
      _showToast('Failed to update: $e', isError: true);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
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
          : _parcel == null
          ? const Center(child: Text('No data'))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final p = _parcel!;
    final status = p['status'] as String? ?? 'pending';
    final price = (p['price'] as num?)?.toDouble() ?? 0;
    final commission = price * 0.30;
    final earnings = price - commission;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: p['photoUrl'] != null && p['photoUrl'].toString().isNotEmpty
                ? Image.network(
                    p['photoUrl'],
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(),
                  )
                : _imagePlaceholder(),
          ),
          const SizedBox(height: 16),

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
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _RouteBox(city: p['fromCity'] ?? '?', label: 'From'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
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

          _infoCard(
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
              ],
            ),
          ),
          const SizedBox(height: 16),

          _infoCard(
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
                      icon: Icons.category_outlined,
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

          _infoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Receiver Details',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _text1,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.person_outline,
                  label: 'Name',
                  value: p['receiverName'] ?? '—',
                ),
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: p['receiverPhone'] ?? '—',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_teal.withOpacity(0.1), _indigo.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _teal.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Parcel Price',
                      style: TextStyle(fontSize: 14, color: _text2),
                    ),
                    Text(
                      '₹${price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _text1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Commission (30%)',
                      style: TextStyle(fontSize: 14, color: _text2),
                    ),
                    Text(
                      '- ₹${commission.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _orange,
                      ),
                    ),
                  ],
                ),
                Divider(color: _teal.withOpacity(0.3), height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'You Earn',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _text1,
                      ),
                    ),
                    Text(
                      '₹${earnings.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Action footer ────────────────────────────────────────────────
          if (status == 'requested') _buildAcceptRejectButtons(),
          if (status == 'accepted') _buildStartPickupButton(),
          if (status == 'picked') _buildDeliverButton(),
          if (status == 'delivered') _buildDeliveredMessage(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _infoCard({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: child,
  );

  Widget _buildAcceptRejectButtons() => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _updating ? null : _rejectParcel,
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text(
            'Reject',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _red,
            side: const BorderSide(color: _red),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _updating ? null : _acceptParcel,
          icon: _updating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(
            _updating ? 'Accepting...' : 'Accept',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _indigo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 2,
          ),
        ),
      ),
    ],
  );

  Widget _buildStartPickupButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: _updating ? null : _startPickup,
      icon: _updating
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.local_shipping_rounded, size: 20),
      label: Text(
        _updating ? 'Starting...' : 'Start Pickup',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
      ),
    ),
  );

  Widget _buildDeliverButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _updating ? null : _markAsDelivered,
      style: ElevatedButton.styleFrom(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
      ),
      child: _updating
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
                SizedBox(width: 12),
                Text('Updating...', style: TextStyle(fontSize: 16)),
              ],
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, size: 20),
                SizedBox(width: 8),
                Text(
                  'Mark as Delivered',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
    ),
  );

  Widget _buildDeliveredMessage() => Container(
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

  Widget _imagePlaceholder() => Container(
    height: 180,
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
        label = 'Requested';
        icon = Icons.pending_actions_rounded;
        break;
      case 'accepted':
        color = _indigo;
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
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat('dd MMM').format(dt);
  }
}

// ── Shared helper widgets ──────────────────────────────────────────────────────
class _RouteBox extends StatelessWidget {
  final String city, label;
  const _RouteBox({required this.city, required this.label});
  @override
  Widget build(BuildContext context) => Container(
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

class _SpecItem extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _SpecItem({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Expanded(
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Padding(
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

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});
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
