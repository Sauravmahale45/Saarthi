// lib/features/parcels/parcel_details_screen.dart
//
// Saarthi – Professional Parcel Details Screen
// Sections:
//   1. Hero Parcel Card (image banner + overlay)
//   2. Delivery Progress Tracker (horizontal steps)
//   3. Route Card (pickup → drop with distance/ETA)
//   4. Parcel Information Grid (2-col)
//   5. Delivery Timeline (chronological)
//   6. Receiver Card (name + mobile) — always visible
//   7. Traveler Card (accepted/picked — name, mobile, email + call/message)
//   8. Pickup OTP Card (large OTP + copy)
//   9. Action Buttons (status-dependent)

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../tracking/parcel_tracking_screen.dart';

// ── Brand tokens ───────────────────────────────────────────────────────────
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

// ════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════════════════════

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

  StreamSubscription<DocumentSnapshot>? _parcelSub;

  @override
  void initState() {
    super.initState();
    _parcelSub = FirebaseFirestore.instance
        .collection('parcels')
        .doc(widget.parcelId)
        .snapshots()
        .listen(
          _onParcelUpdate,
          onError: (e) {
            setState(() {
              _error = e.toString();
              _loading = false;
            });
          },
        );
  }

  void _onParcelUpdate(DocumentSnapshot snap) {
    if (!snap.exists) {
      setState(() {
        _error = 'Parcel not found.';
        _loading = false;
      });
      return;
    }

    final data = snap.data()! as Map<String, dynamic>;
    setState(() {
      _parcel = data;
      _loading = false;
    });

    final travelerId = data['travelerId'] as String?;
    final status = data['status'] as String? ?? '';
    final shouldLoad = travelerId != null;

    if (shouldLoad && travelerId != _previousTravelerId) {
      _previousTravelerId = travelerId;
      _fetchTraveler(travelerId);
    } else if (!shouldLoad) {
      setState(() => _traveler = null);
    }
  }

  Future<void> _fetchTraveler(String uid) async {
    setState(() => _loadingTraveler = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists && mounted) setState(() => _traveler = doc.data());
    } catch (e) {
      debugPrint('Traveler fetch error: $e');
    } finally {
      if (mounted) setState(() => _loadingTraveler = false);
    }
  }

  @override
  void dispose() {
    _parcelSub?.cancel();
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

  // ── Coordinate helpers ────────────────────────────────────────────────────

  LatLng? get _pickupLatLng {
    final p = _parcel;
    if (p == null) return null;
    final pickup = p['pickup'] as Map<String, dynamic>?;
    if (pickup != null) {
      final lat = (pickup['lat'] as num?)?.toDouble();
      final lng = (pickup['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    final lat = (p['pickupLat'] as num?)?.toDouble();
    final lng = (p['pickupLng'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  LatLng? get _dropLatLng {
    final p = _parcel;
    if (p == null) return null;
    final drop = p['drop'] as Map<String, dynamic>?;
    if (drop != null) {
      final lat = (drop['lat'] as num?)?.toDouble();
      final lng = (drop['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    final lat =
        (p['dropLat'] as num?)?.toDouble() ?? (p['toLat'] as num?)?.toDouble();
    final lng =
        (p['dropLng'] as num?)?.toDouble() ?? (p['toLng'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  double? get _distanceKm {
    final a = _pickupLatLng;
    final b = _dropLatLng;
    if (a == null || b == null) return null;
    return _haversineKm(a, b);
  }

  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(a.latitude)) *
            math.cos(_deg2rad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _deg2rad(double d) => d * math.pi / 180;

  // ── Address helpers ───────────────────────────────────────────────────────

  String _pickupAddress(Map<String, dynamic> p) {
    final pickup = p['pickup'] as Map<String, dynamic>?;
    return pickup?['address'] as String? ?? p['pickupAddress'] as String? ?? '';
  }

  String _dropAddress(Map<String, dynamic> p) {
    final drop = p['drop'] as Map<String, dynamic>?;
    return drop?['address'] as String? ?? p['dropAddress'] as String? ?? '';
  }

  String _pickupCity(Map<String, dynamic> p) {
    final pickup = p['pickup'] as Map<String, dynamic>?;
    return pickup?['city'] as String? ?? p['fromCity'] as String? ?? '?';
  }

  String _dropCity(Map<String, dynamic> p) {
    final drop = p['drop'] as Map<String, dynamic>?;
    return drop?['city'] as String? ?? p['toCity'] as String? ?? '?';
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _indigo))
          : _error != null
          ? _ErrorView(error: _error!, onBack: () => context.pop())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final p = _parcel!;
    final status = p['status'] as String? ?? 'pending';

    return CustomScrollView(
      slivers: [
        // ── Collapsing hero app bar ─────────────────────────────────────
        SliverAppBar(
          expandedHeight: 260,
          pinned: true,
          backgroundColor: _indigo,
          leading: GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          title: const Text(
            'Parcel Details',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: _buildHeroBanner(p, status),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // S2: Progress tracker
              _buildProgressTracker(status),
              const SizedBox(height: 20),

              // S3: Route card
              _buildRouteCard(p),
              const SizedBox(height: 16),

              // S4: Info grid
              _buildInfoGrid(p),
              const SizedBox(height: 16),

              // S5: Timeline
              _buildTimeline(p),
              const SizedBox(height: 16),

              // S6: Receiver card — always shown
              _buildReceiverCard(p),
              const SizedBox(height: 16),

              // S7: Traveler card — accepted / picked only
              if ([
                'requested',
                'accepted',
                'picked',
                'delivered',
              ].contains(status)) ...[
                _buildTravelerCard(status),
                const SizedBox(height: 16),
              ],

              // S8: OTP card
              if (p['pickupStarted'] == true && p['pickupOTP'] != null) ...[
                _buildOTPCard(p),
                const SizedBox(height: 16),
              ],

              // S9: Action buttons
              _buildActionButtons(p, status),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  S1 – HERO BANNER
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildHeroBanner(Map<String, dynamic> p, String status) {
    final photoUrl = p['photoUrl'] as String? ?? '';
    final category = p['category'] as String? ?? 'Parcel';
    final subCat = p['subCategory'] as String? ?? '';
    final from = _pickupCity(p);
    final to = _dropCity(p);

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: photoUrl.isNotEmpty
              ? Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : Container(
                          color: const Color(0xFF3730A3),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white54,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                  errorBuilder: (_, __, ___) => _heroBannerPlaceholder(),
                )
              : _heroBannerPlaceholder(),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 130,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xDD000000), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _HeroChip(label: category, color: _orange),
                  if (subCat.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _HeroChip(label: subCat, color: _teal),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: Colors.white70,
                    size: 14,
                  ),
                  Text(
                    ' $from ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white54,
                    size: 13,
                  ),
                  Text(
                    ' $to',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _PriceBadge(price: p['price']),
                  const SizedBox(width: 8),
                  _StatusBadge(status: status),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroBannerPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3730A3), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.inventory_2_outlined,
          color: Colors.white38,
          size: 72,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  S2 – DELIVERY PROGRESS TRACKER
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildProgressTracker(String status) {
    const steps = [
      _ProgressStep(label: 'Posted', icon: Icons.add_circle_outline_rounded),
      _ProgressStep(label: 'Accepted', icon: Icons.person_pin_rounded),
      _ProgressStep(label: 'Picked', icon: Icons.inventory_2_rounded),
      _ProgressStep(label: 'Transit', icon: Icons.local_shipping_rounded),
      _ProgressStep(label: 'Delivered', icon: Icons.check_circle_rounded),
    ];

    final activeIndex = _statusToStep(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: _cardDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(text: 'Delivery Progress'),
          const SizedBox(height: 16),
          Row(
            children: List.generate(steps.length * 2 - 1, (i) {
              if (i.isOdd) {
                final filled = (i ~/ 2) < activeIndex;
                return Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: filled ? _green : _border,
                    ),
                  ),
                );
              }
              final idx = i ~/ 2;
              final isDone = idx < activeIndex;
              final isActive = idx == activeIndex;
              return _ProgressDot(
                step: steps[idx],
                isDone: isDone,
                isActive: isActive,
              );
            }),
          ),
        ],
      ),
    );
  }

  int _statusToStep(String status) {
    switch (status) {
      case 'pending':
        return 0;
      case 'requested':
      case 'accepted':
        return 1;
      case 'picked':
        return 2;
      case 'in_transit':
        return 3;
      case 'delivered':
        return 4;
      default:
        return 0;
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  S3 – ROUTE CARD
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildRouteCard(Map<String, dynamic> p) {
    final fromCity = _pickupCity(p);
    final fromAddress = _pickupAddress(p);
    final toCity = _dropCity(p);
    final toAddress = _dropAddress(p);
    final km = _distanceKm;
    final eta = km != null ? (km / 50 * 60).ceil() : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(text: 'Route'),
          const SizedBox(height: 14),

          _RouteStop(
            icon: Icons.trip_origin_rounded,
            color: _indigo,
            label: 'PICKUP',
            city: fromCity,
            address: fromAddress,
          ),

          Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),
                if (km != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _teal.withOpacity(0.3)),
                    ),
                    child: Text(
                      '${km.toStringAsFixed(0)} km  •  approx '
                      '${eta! >= 60 ? '${eta ~/ 60}h ${eta % 60}m' : '${eta}m'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _teal,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          _RouteStop(
            icon: Icons.location_on_rounded,
            color: _green,
            label: 'DROP',
            city: toCity,
            address: toAddress,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  S4 – PARCEL INFORMATION GRID
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildInfoGrid(Map<String, dynamic> p) {
    final deadline = p['deliveryDeadline'] as Timestamp?;
    final deadlineStr = deadline != null
        ? DateFormat('dd MMM, HH:mm').format(deadline.toDate())
        : '—';

    final items = [
      _GridItem(
        label: 'Weight',
        value: '${p['weight'] ?? '—'} kg',
        icon: Icons.scale_outlined,
        color: _indigo,
      ),
      _GridItem(
        label: 'Size',
        value: p['size'] ?? '—',
        icon: Icons.straighten_outlined,
        color: _teal,
      ),
      _GridItem(
        label: 'Category',
        value: p['category'] ?? '—',
        icon: Icons.category_outlined,
        color: _orange,
      ),
      _GridItem(
        label: 'Sub-Category',
        value: p['subCategory'] ?? '—',
        icon: Icons.label_outline_rounded,
        color: _indigo,
      ),
      _GridItem(
        label: 'Price',
        value: '₹${p['price'] ?? 0}',
        icon: Icons.currency_rupee_rounded,
        color: _green,
      ),
      _GridItem(
        label: 'Deadline',
        value: deadlineStr,
        icon: Icons.timer_outlined,
        color: _red,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(text: 'Parcel Info'),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.4,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _InfoGridTile(item: items[i]),
          ),
          if ((p['description'] as String? ?? '').isNotEmpty) ...[
            const Divider(color: _border, height: 24),
            Text(
              p['description'],
              style: const TextStyle(fontSize: 13, color: _text2, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  S5 – DELIVERY TIMELINE
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildTimeline(Map<String, dynamic> p) {
    final events = <_TimelineEvent>[
      _TimelineEvent(
        label: 'Parcel Posted',
        icon: Icons.add_circle_outline_rounded,
        color: _indigo,
        ts: p['createdAt'] as Timestamp?,
      ),
      if (p['acceptedAt'] != null)
        _TimelineEvent(
          label: 'Traveler Accepted',
          icon: Icons.person_pin_rounded,
          color: _teal,
          ts: p['acceptedAt'] as Timestamp?,
        ),
      if (p['pickedAt'] != null)
        _TimelineEvent(
          label: 'Picked Up',
          icon: Icons.inventory_2_rounded,
          color: _orange,
          ts: p['pickedAt'] as Timestamp?,
        ),
      if (p['deliveredAt'] != null)
        _TimelineEvent(
          label: 'Delivered',
          icon: Icons.check_circle_rounded,
          color: _green,
          ts: p['deliveredAt'] as Timestamp?,
        ),
    ];

    if (events.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(text: 'Journey Timeline'),
          const SizedBox(height: 14),
          ...List.generate(
            events.length,
            (i) =>
                _TimelineTile(event: events[i], isLast: i == events.length - 1),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  S6 – RECEIVER CARD
  //  Reads:  receiverName, receiverPhone  from Firestore parcel document.
  //  Always shown (hides itself if both fields are empty).
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildReceiverCard(Map<String, dynamic> p) {
    final name = (p['receiverName'] as String? ?? '').trim();
    final phone = (p['receiverPhone'] as String? ?? '').trim();

    if (name.isEmpty && phone.isEmpty) return const SizedBox.shrink();

    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _teal.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: _teal,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Receiver',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _text1,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              // Avatar circle
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: _teal.withOpacity(0.3), width: 1.5),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _teal,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Name + phone column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty)
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _text1,
                        ),
                      ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _ContactRow(
                        icon: Icons.phone_outlined,
                        label: 'Mobile',
                        value: phone,
                        color: _teal,
                      ),
                    ],
                  ],
                ),
              ),

              // Quick-call button
              if (phone.isNotEmpty)
                GestureDetector(
                  onTap: () => _toast('Calling $phone…'),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _teal.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: _teal.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      Icons.call_rounded,
                      color: _teal,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  S7 – TRAVELER CARD
  //  Shown only when status is requested / accepted / picked.
  //  Displays: avatar, name, star rating, mobile, email,
  //            Call + Message action buttons.
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildTravelerCard(String status) {
    if (_loadingTraveler) {
      return Container(
        height: 88,
        decoration: _cardDecor(),
        child: const Center(
          child: CircularProgressIndicator(color: _indigo, strokeWidth: 2),
        ),
      );
    }

    if (_traveler == null) return const SizedBox.shrink();

    final t = _traveler!;
    final name =
        (t['name'] as String? ?? t['displayName'] as String? ?? 'Traveler')
            .trim();
    final email = (t['email'] as String? ?? '').trim();
    final phone = (t['phone'] as String? ?? '').trim();
    final photo = (t['photoUrl'] as String? ?? '').trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'T';

    // Colour shifts by status: teal = requested/accepted, indigo = picked
    final Color accent = status == 'picked' ? _indigo : _teal;

    final String cardTitle = status == 'picked'
        ? 'Traveler — Parcel Picked Up'
        : status == 'accepted'
        ? 'Assigned Traveler'
        : 'Requested Traveler';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dynamic section label
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cardTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _text1,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Avatar + name + rating row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              CircleAvatar(
                radius: 26,
                backgroundColor: accent.withOpacity(0.12),
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty
                    ? Text(
                        initial,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),

              // Name + stars
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _text1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < 4 ? Icons.star_rounded : Icons.star_half_rounded,
                          size: 13,
                          color: _orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(color: _border, height: 1),
          const SizedBox(height: 12),

          // Contact details
          if (phone.isNotEmpty)
            _ContactRow(
              icon: Icons.phone_outlined,
              label: 'Mobile',
              value: phone,
              color: accent,
            ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ContactRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: email,
              color: accent,
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  S8 – PICKUP OTP CARD
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildOTPCard(Map<String, dynamic> p) {
    final otp = p['pickupOTP'] as String? ?? '—';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _indigo.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: _indigo.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_indigo, _indigoL],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _indigo.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.security_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pickup Verification',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _text1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Share this OTP with the traveler when they arrive.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _text2),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
            decoration: BoxDecoration(
              color: _indigo.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _indigo.withOpacity(0.2)),
            ),
            child: Text(
              otp.split('').join('  '),
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                color: _indigo,
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: otp));
              _toast('OTP copied!');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                color: _indigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _indigo.withOpacity(0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, color: _indigo, size: 15),
                  SizedBox(width: 6),
                  Text(
                    'Copy OTP',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _indigo,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  S9 – ACTION BUTTONS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildActionButtons(Map<String, dynamic> p, String status) {
    switch (status) {
      case 'pending':
        return _PrimaryButton(
          icon: Icons.search_rounded,
          label: 'Find Travelers',
          color: _indigo,
          onTap: () => context.push('/available-traveler/${widget.parcelId}'),
        );

      case 'requested':
      case 'accepted':
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _teal.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _teal.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: _teal, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status == 'accepted'
                      ? 'Traveler accepted. Arrange pickup with them.'
                      : 'Waiting for traveler to confirm your request.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _teal,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );

      case 'picked':
        return Column(
          children: [
            _PrimaryButton(
              icon: Icons.payment_rounded,
              label: 'Make Payment',
              color: _green,
              onTap: () => context.push('/make-payment/${widget.parcelId}'),
            ),
            const SizedBox(height: 10),
            _SecondaryButton(
              icon: Icons.radar_rounded,
              label: 'Track Parcel Live',
              color: _indigo,
              onTap: () {
                if (_traveler == null || _dropLatLng == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ParcelTrackingScreen(
                      parcelId: widget.parcelId,
                      destLat: _dropLatLng!.latitude,
                      destLng: _dropLatLng!.longitude,
                      destLabel: _dropCity(p),
                      travelerName:
                          _traveler!['name'] ??
                          _traveler!['displayName'] ??
                          'Traveler',
                    ),
                  ),
                );
              },
            ),
          ],
        );

      case 'delivered':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _green.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _green.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, color: _green, size: 22),
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

      default:
        return const SizedBox.shrink();
    }
  }

  BoxDecoration _cardDecor({bool padding = true}) => BoxDecoration(
    color: _card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

class _ProgressStep {
  final String label;
  final IconData icon;
  const _ProgressStep({required this.label, required this.icon});
}

class _GridItem {
  final String label, value;
  final IconData icon;
  final Color color;
  const _GridItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _TimelineEvent {
  final String label;
  final IconData icon;
  final Color color;
  final Timestamp? ts;
  const _TimelineEvent({
    required this.label,
    required this.icon,
    required this.color,
    required this.ts,
  });
}

// ════════════════════════════════════════════════════════════════════════════
//  REUSABLE WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: _indigo,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _text1,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

// ── Labelled contact row (icon badge + label + value) ─────────────────────
class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: _text2,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _text1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  final Color color;
  const _HeroChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  final dynamic price;
  const _PriceBadge({required this.price});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '₹${price ?? 0}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c;
    String label;
    switch (status) {
      case 'pending':
        c = _orange;
        label = 'Pending';
        break;
      case 'requested':
        c = _teal;
        label = 'Requested';
        break;
      case 'accepted':
        c = _green;
        label = 'Accepted';
        break;
      case 'picked':
        c = _indigo;
        label = 'Picked Up';
        break;
      case 'delivered':
        c = _green;
        label = 'Delivered';
        break;
      default:
        c = _text2;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ProgressDot extends StatelessWidget {
  final _ProgressStep step;
  final bool isDone, isActive;
  const _ProgressDot({
    required this.step,
    required this.isDone,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = isDone ? _green : (isActive ? _indigo : _border);
    final Color icon = (isDone || isActive) ? Colors.white : _text2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isActive ? 34 : 28,
          height: isActive ? 34 : 28,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: isActive || isDone
                ? [
                    BoxShadow(
                      color: bg.withOpacity(0.35),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Icon(step.icon, color: icon, size: isActive ? 18 : 14),
        ),
        const SizedBox(height: 5),
        Text(
          step.label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? _indigo : (isDone ? _green : _text2),
          ),
        ),
      ],
    );
  }
}

class _RouteStop extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, city, address;
  const _RouteStop({
    required this.icon,
    required this.color,
    required this.label,
    required this.city,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                city,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _text1,
                ),
              ),
              if (address.isNotEmpty)
                Text(
                  address,
                  style: const TextStyle(fontSize: 12, color: _text2),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoGridTile extends StatelessWidget {
  final _GridItem item;
  const _InfoGridTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: item.color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: item.color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _text2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: item.color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final _TimelineEvent event;
  final bool isLast;
  const _TimelineTile({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final dt = event.ts?.toDate();
    final str = dt != null ? DateFormat('dd MMM, HH:mm').format(dt) : 'Pending';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: event.color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: event.color.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Icon(event.icon, color: event.color, size: 16),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    event.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _text1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    str,
                    style: const TextStyle(fontSize: 11, color: _text2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onBack;
  const _ErrorView({required this.error, required this.onBack});

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
}
