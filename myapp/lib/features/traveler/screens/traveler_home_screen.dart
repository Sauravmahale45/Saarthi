import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

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

// ── Cloudinary config ─────────────────────────────────────────────────────────
const _cloudName = 'dwjzuw8fd';
const _uploadPreset = 'kyc_upload';

/// How long a traveler has to respond before the request auto-expires.
const _kRequestExpiry = Duration(minutes: 15);

// ════════════════════════════════════════════════════════════════════════════
//  ROOT SCREEN
// ════════════════════════════════════════════════════════════════════════════
class TravelerHomeScreen extends StatefulWidget {
  const TravelerHomeScreen({super.key});

  @override
  State<TravelerHomeScreen> createState() => _TravelerHomeScreenState();
}

class _TravelerHomeScreenState extends State<TravelerHomeScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;

  int _navIndex = 0;
  bool _kycVerified = false;
  bool _locationGranted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _syncVerificationFromFirestore();
  }

  Future<void> _syncVerificationFromFirestore() async {
    final uid = _user?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final d = snap.data() ?? {};
      setState(() {
        _kycVerified = d['kycVerified'] == true;
        _locationGranted = d['locationGranted'] == true;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _requestRealLocation() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      _toast(
        '📍 Please turn on Location / GPS in your device settings.',
        isError: true,
      );
      await Geolocator.openLocationSettings();
      return;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) {
      _toast(
        'Location blocked. Open Settings and allow location for Saarthi.',
        isError: true,
      );
      await openAppSettings();
      return;
    }
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Location permission denied.', isError: true);
        return;
      }
    }
    try {
      _toast('📍 Getting your location…');
      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      await FirebaseFirestore.instance.collection('users').doc(_user!.uid).set({
        'locationGranted': true,
        'lastLatitude': pos.latitude,
        'lastLongitude': pos.longitude,
        'locationAccuracy': pos.accuracy,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _locationGranted = true);
      _toast(
        '📍 Location saved (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})',
      );
    } on LocationServiceDisabledException {
      _toast('GPS is disabled.', isError: true);
    } on PermissionDeniedException {
      _toast('Permission denied.', isError: true);
    } catch (e) {
      _toast('Location error: $e', isError: true);
    }
  }

  Future<void> _updateDeliveryStatus(String parcelId, String newStatus) async {
    await FirebaseFirestore.instance.collection('parcels').doc(parcelId).update(
      {'status': newStatus, 'updatedAt': FieldValue.serverTimestamp()},
    );
    if (newStatus == 'delivered') {
      await _markRouteInactive(parcelId);
    }
  }

  Future<void> _markRouteInactive(String parcelId) async {
    try {
      final parcelSnap = await FirebaseFirestore.instance
          .collection('parcels')
          .doc(parcelId)
          .get();
      if (!parcelSnap.exists) return;
      final data = parcelSnap.data()!;
      final travelerId = data['travelerId'] as String?;
      final fromCity = data['fromCity'] as String?;
      final toCity = data['toCity'] as String?;
      if (travelerId == null) return;
      final routeQuery = await FirebaseFirestore.instance
          .collection('travelRoutes')
          .where('travelerId', isEqualTo: travelerId)
          .where('fromCity', isEqualTo: fromCity)
          .where('toCity', isEqualTo: toCity)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (routeQuery.docs.isNotEmpty) {
        await routeQuery.docs.first.reference.update({'status': 'inactive'});
      }
    } catch (e) {
      debugPrint('_markRouteInactive error: $e');
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go('/login');
  }

  // ── Firestore streams ──────────────────────────────────────────────────────
  Stream<QuerySnapshot> get _incomingRequests => FirebaseFirestore.instance
      .collection('parcels')
      .where('status', isEqualTo: 'requested')
      .where('travelerId', isEqualTo: _user?.uid)
      .snapshots();

  Stream<QuerySnapshot> get _myDeliveries => FirebaseFirestore.instance
      .collection('parcels')
      .where('travelerId', isEqualTo: _user?.uid)
      .where('status', whereIn: ['accepted', 'picked'])
      .snapshots();

  Stream<QuerySnapshot> get _completedDeliveries => FirebaseFirestore.instance
      .collection('parcels')
      .where('travelerId', isEqualTo: _user?.uid)
      .where('status', isEqualTo: 'delivered')
      .snapshots();

  Stream<QuerySnapshot> get _myRoutes => FirebaseFirestore.instance
      .collection('travelRoutes')
      .where('travelerId', isEqualTo: _user?.uid)
      .orderBy('travelDateTime', descending: true)
      .snapshots();

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

  void _showSetupSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _SetupSheet(
        uid: _user?.uid ?? '',
        locationGranted: _locationGranted,
        kycVerified: _kycVerified,
        onLocationTap: () async {
          Navigator.pop(ctx);
          await _requestRealLocation();
        },
        onKycVerified: () {
          setState(() => _kycVerified = true);
          _toast('✅ KYC submitted! You can now accept parcels.');
        },
      ),
    );
  }

  void _showAddRouteSheet() {
    String from = 'Nashik', to = 'Pune';
    final spaceCtrl = TextEditingController();
    const routeCities = ['Nashik', 'Pune', 'Mumbai', 'Aurangabad', 'Nagpur'];
    DateTime? selectedDate;
    TimeOfDay? selectedTime;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, ss) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _Handle()),
              const SizedBox(height: 20),
              const Text(
                'Add Travel Route',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _text1,
                ),
              ),
              const Text(
                'Tell us your journey so we can match parcels.',
                style: TextStyle(fontSize: 13, color: _text2),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _SheetDropdown(
                      label: 'From',
                      value: from,
                      items: routeCities,
                      onChanged: (v) => ss(() => from = v!),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _indigo.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: _indigo,
                      size: 16,
                    ),
                  ),
                  Expanded(
                    child: _SheetDropdown(
                      label: 'To',
                      value: to,
                      items: routeCities,
                      onChanged: (v) => ss(() => to = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) ss(() => selectedDate = picked);
                },
                child: _PickerField(
                  icon: Icons.calendar_today_outlined,
                  text: selectedDate != null
                      ? DateFormat('dd/MM/yyyy').format(selectedDate!)
                      : 'Select travel date',
                  hasValue: selectedDate != null,
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: selectedTime ?? TimeOfDay.now(),
                  );
                  if (picked != null) ss(() => selectedTime = picked);
                },
                child: _PickerField(
                  icon: Icons.access_time_outlined,
                  text: selectedTime != null
                      ? selectedTime!.format(context)
                      : 'Select travel time',
                  hasValue: selectedTime != null,
                ),
              ),
              const SizedBox(height: 12),
              _SheetField(
                ctrl: spaceCtrl,
                hint: 'Available bag space (kg)',
                icon: Icons.luggage_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              _PrimaryBtn(
                label: 'Save Route',
                onTap: () async {
                  final uid = _user?.uid;
                  if (uid == null) return;
                  if (selectedDate == null || selectedTime == null) {
                    _toast('Please select both date and time', isError: true);
                    return;
                  }
                  final travelDateTime = DateTime(
                    selectedDate!.year,
                    selectedDate!.month,
                    selectedDate!.day,
                    selectedTime!.hour,
                    selectedTime!.minute,
                  );
                  await FirebaseFirestore.instance
                      .collection('travelRoutes')
                      .add({
                        'travelerId': uid,
                        'travelerName': _user?.displayName ?? '',
                        'fromCity': from,
                        'toCity': to,
                        'travelDateTime': Timestamp.fromDate(travelDateTime),
                        'bagSpaceKg': double.tryParse(spaceCtrl.text) ?? 0,
                        'status': 'active',
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast('🗺️ Route saved! You\'ll be matched with parcels.');
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HANDLE INCOMING REQUESTS
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _handleRequest(String parcelId, bool accept) async {
    if (!_kycVerified || !_locationGranted) {
      _showSetupSheet();
      return;
    }
    try {
      if (accept) {
        // Read-before-write guard
        final freshSnap = await FirebaseFirestore.instance
            .collection('parcels')
            .doc(parcelId)
            .get();
        if (!freshSnap.exists) {
          _toast('This request no longer exists.', isError: true);
          return;
        }
        final freshData = freshSnap.data()!;
        final currentStatus = freshData['status'] as String? ?? '';
        final currentTravelerId = freshData['travelerId'] as String? ?? '';
        if (currentStatus != 'requested' || currentTravelerId != _user?.uid) {
          _toast('This request is no longer available.', isError: true);
          return;
        }
        await FirebaseFirestore.instance
            .collection('parcels')
            .doc(parcelId)
            .update({
              'status': 'accepted',
              'acceptedAt': FieldValue.serverTimestamp(),
            });
        _toast('✅ Request accepted. Contact sender for pickup.');
      } else {
        // Reject → add to ignoredTravelers
        await FirebaseFirestore.instance
            .collection('parcels')
            .doc(parcelId)
            .update({
              'status': 'pending',
              'travelerId': null,
              'travelerName': null,
              'ignoredTravelers': FieldValue.arrayUnion([_user!.uid]),
            });
        _toast('⛔ Request rejected.');
      }
    } catch (e) {
      _toast('Failed: $e', isError: true);
    }
  }

  /// Called when a request expires (traveler ignored it for 15 min).
  /// Resets parcel and adds traveler to ignoredTravelers.
  Future<void> _expireRequest(String parcelId, String travelerId) async {
    try {
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(parcelId)
          .update({
            'status': 'pending',
            'travelerId': null,
            'travelerName': null,
            'ignoredTravelers': FieldValue.arrayUnion([travelerId]),
          });
    } catch (e) {
      debugPrint('_expireRequest error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _indigo)),
      );
    }

    final tabs = [
      _HomeTab(
        user: _user,
        kycVerified: _kycVerified,
        locationGranted: _locationGranted,
        incomingStream: _incomingRequests,
        activeStream: _myDeliveries,
        completedStream: _completedDeliveries,
        onHandleRequest: _handleRequest,
        onExpireRequest: _expireRequest,
        onUpdateStatus: _updateDeliveryStatus,
        onAddRouteTap: _showAddRouteSheet,
        onSetupTap: _showSetupSheet,
      ),
      _DeliveriesTab(
        stream: _myDeliveries,
        onUpdateStatus: _updateDeliveryStatus,
      ),
      _WalletTab(completedStream: _completedDeliveries),
      _RoutesTab(stream: _myRoutes),
      _ProfileTab(
        user: _user,
        kycVerified: _kycVerified,
        locationGranted: _locationGranted,
        onSetupTap: _showSetupSheet,
        onSignOut: _signOut,
        onSwitchSender: () => context.go('/sender'),
      ),
    ];

    return Scaffold(
      backgroundColor: _bg,
      body: tabs[_navIndex],
      bottomNavigationBar: _BottomNav(
        index: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SETUP SHEET (unchanged)
// ════════════════════════════════════════════════════════════════════════════
class _SetupSheet extends StatefulWidget {
  final String uid;
  final bool locationGranted;
  final bool kycVerified;
  final Future<void> Function() onLocationTap;
  final VoidCallback onKycVerified;
  const _SetupSheet({
    required this.uid,
    required this.locationGranted,
    required this.kycVerified,
    required this.onLocationTap,
    required this.onKycVerified,
  });
  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  File? _kycFile;
  bool _uploading = false;
  String _docType = 'Aadhaar Card';
  static const _docTypes = [
    'Aadhaar Card',
    'PAN Card',
    'Voter ID',
    'Driving Licence',
    'Passport',
  ];

  Future<void> _pickImage(ImageSource source) async {
    final perm = source == ImageSource.camera
        ? await Permission.camera.request()
        : await Permission.photos.request();
    if (!perm.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied. Please allow in Settings.'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await openAppSettings();
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1400,
    );
    if (picked != null) setState(() => _kycFile = File(picked.path));
  }

  Future<void> _submitKyc() async {
    if (_kycFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a document photo first.'),
          backgroundColor: _orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
      );
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder'] = 'kyc_docs'
        ..fields['context'] = 'uid=${widget.uid}|docType=$_docType'
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            _kycFile!.path,
            filename: 'kyc_${widget.uid}.jpg',
          ),
        );
      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        throw Exception(
          'Cloudinary error ${response.statusCode}: ${response.body}',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'kycDocUrl': body['secure_url'],
        'kycDocPublicId': body['public_id'],
        'kycDocType': _docType,
        'kycStatus': 'submitted',
        'kycVerified': true,
        'kycSubmittedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      widget.onKycVerified();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Handle(),
            const SizedBox(height: 16),
            const Text(
              'Choose Source',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _text1,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SourceCard(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceCard(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Handle(),
            const SizedBox(height: 20),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: _indigo.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                color: _indigo,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Complete Setup to Accept Parcels',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _text1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Both steps are required to protect senders\nand ensure trusted deliveries.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _text2, height: 1.5),
            ),
            const SizedBox(height: 24),
            _StepTile(
              stepNum: '1',
              icon: Icons.location_on_outlined,
              color: _teal,
              title: 'Allow Location Access',
              subtitle: 'Shares your live GPS position with senders',
              done: widget.locationGranted,
              buttonLabel: 'Grant Now',
              onTap: widget.locationGranted ? null : widget.onLocationTap,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.kycVerified
                    ? _green.withOpacity(0.04)
                    : _indigo.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.kycVerified
                      ? _green.withOpacity(0.25)
                      : _indigo.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StepCircle(num: '2', done: widget.kycVerified),
                      const SizedBox(width: 10),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: (widget.kycVerified ? _green : _indigo)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.kycVerified
                              ? Icons.check_circle_rounded
                              : Icons.badge_outlined,
                          color: widget.kycVerified ? _green : _indigo,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'KYC Verification',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: widget.kycVerified ? _green : _text1,
                              ),
                            ),
                            Text(
                              widget.kycVerified
                                  ? 'Document uploaded & verified ✓'
                                  : 'Upload a valid Govt ID (Aadhaar / PAN / Voter ID)',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!widget.kycVerified) ...[
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFFE2E8F0), height: 1),
                    const SizedBox(height: 16),
                    const Text(
                      'Document Type',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _text2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _docType,
                          isExpanded: true,
                          style: const TextStyle(
                            fontSize: 14,
                            color: _text1,
                            fontWeight: FontWeight.w500,
                          ),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: _text2,
                          ),
                          items: _docTypes
                              .map(
                                (t) =>
                                    DropdownMenuItem(value: t, child: Text(t)),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _docType = v!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _showSourcePicker,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        height: _kycFile != null ? 190 : 110,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _kycFile != null
                                ? _indigo.withOpacity(0.5)
                                : const Color(0xFFCBD5E1),
                            width: _kycFile != null ? 1.5 : 1,
                          ),
                        ),
                        child: _kycFile != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(13),
                                    child: Image.file(
                                      _kycFile!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: _showSourcePicker,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.edit_outlined,
                                              color: Colors.white,
                                              size: 12,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Change',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: _indigo.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.upload_file_outlined,
                                      color: _indigo,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Tap to upload document photo',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _indigo,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Camera or Gallery • JPG/PNG',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _text2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _uploading ? null : _submitKyc,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _indigo,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _indigo.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _uploading
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
                                  SizedBox(width: 12),
                                  Text(
                                    'Uploading…',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              )
                            : const Text(
                                'Submit KYC Document',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _green.withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: _green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your document is encrypted & stored securely on Cloudinary. '
                      'Used only for identity verification.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF166534),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  HOME TAB
// ════════════════════════════════════════════════════════════════════════════
class _HomeTab extends StatelessWidget {
  final User? user;
  final bool kycVerified, locationGranted;
  final Stream<QuerySnapshot> incomingStream;
  final Stream<QuerySnapshot> activeStream, completedStream;
  final Future<void> Function(String, bool) onHandleRequest;
  final Future<void> Function(String, String) onExpireRequest;
  final Future<void> Function(String, String) onUpdateStatus;
  final VoidCallback onAddRouteTap, onSetupTap;

  const _HomeTab({
    required this.user,
    required this.kycVerified,
    required this.locationGranted,
    required this.incomingStream,
    required this.activeStream,
    required this.completedStream,
    required this.onHandleRequest,
    required this.onExpireRequest,
    required this.onUpdateStatus,
    required this.onAddRouteTap,
    required this.onSetupTap,
  });

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  bool get _fullySetup => kycVerified && locationGranted;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 162,
          floating: false,
          pinned: true,
          backgroundColor: _indigo,
          automaticallyImplyLeading: false,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                backgroundImage: user?.photoURL != null
                                    ? NetworkImage(user!.photoURL!)
                                    : null,
                                child: user?.photoURL == null
                                    ? Text(
                                        (user?.displayName ?? 'T')[0]
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                              ),
                              if (_fullySetup)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: const BoxDecoration(
                                      color: _green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 9,
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
                                Text(
                                  '$_greeting 👋',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                                Text(
                                  user?.displayName?.split(' ').first ??
                                      'Traveler',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _HBadge(
                                label: '⭐ 4.8 Rating',
                                bg: Colors.white.withOpacity(0.18),
                              ),
                              const SizedBox(height: 4),
                              _HBadge(
                                label: _fullySetup
                                    ? '✅ Verified'
                                    : '⚠️ Setup Needed',
                                bg: _fullySetup
                                    ? _green.withOpacity(0.3)
                                    : _orange.withOpacity(0.35),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      StreamBuilder<QuerySnapshot>(
                        stream: completedStream,
                        builder: (_, snap) {
                          double total = 0;
                          final n = snap.data?.docs.length ?? 0;
                          for (final d in snap.data?.docs ?? []) {
                            total +=
                                ((d.data() as Map)['price'] as num?)
                                    ?.toDouble() ??
                                0;
                          }
                          return Row(
                            children: [
                              _QStat(label: 'Deliveries', value: '$n'),
                              const SizedBox(width: 20),
                              _QStat(
                                label: 'Total Earned',
                                value: '₹${total.toStringAsFixed(0)}',
                              ),
                              const SizedBox(width: 20),
                              _QStat(
                                label: 'Status',
                                value: _fullySetup ? 'Active' : 'Pending',
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_fullySetup) ...[
                  _SetupBanner(
                    locationGranted: locationGranted,
                    kycVerified: kycVerified,
                    onTap: onSetupTap,
                  ),
                  const SizedBox(height: 16),
                ],
                _AddRouteCard(onTap: onAddRouteTap),
                const SizedBox(height: 22),
                _EarningCard(stream: completedStream),
                const SizedBox(height: 22),

                // ── Incoming Requests ──────────────────────────────────────
                _SectionTitle(icon: '📥', title: 'Incoming Requests'),
                const SizedBox(height: 10),
                StreamBuilder<QuerySnapshot>(
                  stream: incomingStream,
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 50,
                        child: Center(
                          child: CircularProgressIndicator(color: _indigo),
                        ),
                      );
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return _InfoCard(
                        icon: '📭',
                        text: 'No pending requests.',
                        color: _text2,
                      );
                    }
                    return Column(
                      children: snap.data!.docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return _RequestCard(
                          data: data,
                          docId: doc.id,
                          currentUserId:
                              FirebaseAuth.instance.currentUser?.uid ?? '',
                          onHandle: onHandleRequest,
                          onExpire: onExpireRequest,
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 22),

                // ── Active Deliveries ──────────────────────────────────────
                _SectionTitle(icon: '🚌', title: 'Active Deliveries'),
                const SizedBox(height: 10),
                _ActiveSection(
                  stream: activeStream,
                  onUpdateStatus: onUpdateStatus,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  REQUEST CARD  ←  THIS IS WHERE THE TIMER LIVES
//
//  On mount:
//    • If already expired → calls onExpire immediately (Firestore write)
//    • If not yet expired → starts a countdown Timer for the remaining window
//
//  The Timer fires EXACTLY when 15 minutes have elapsed since requestedAt.
//  On fire → calls onExpire which:
//      status = 'pending'
//      travelerId = null
//      travelerName = null
//      ignoredTravelers = arrayUnion([travelerId])
//
//  A 1-second ticker keeps the UI countdown up-to-date until expiry.
//  Both timers are cancelled in dispose() — no leaks.
// ════════════════════════════════════════════════════════════════════════════
class _RequestCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String currentUserId;
  final Future<void> Function(String, bool) onHandle;
  final Future<void> Function(String, String) onExpire;

  const _RequestCard({
    required this.data,
    required this.docId,
    required this.currentUserId,
    required this.onHandle,
    required this.onExpire,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  // ── Timer state ────────────────────────────────────────────────────────────
  Timer? _expiryTimer; // fires once at the exact expiry moment
  Timer? _tickTimer; // fires every second to refresh the countdown label
  Duration _remaining = Duration.zero;
  bool _expired = false;
  bool _handling = false;
  bool _expiryCalled = false; // guard so we only call onExpire once

  @override
  void initState() {
    super.initState();
    _initTimer();
  }

  @override
  void didUpdateWidget(_RequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parcel document is updated (e.g. re-sent) restart the timer.
    if (oldWidget.data['requestedAt'] != widget.data['requestedAt']) {
      _cancelTimers();
      _expiryCalled = false;
      _expired = false;
      _initTimer();
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _expiryTimer?.cancel();
    _tickTimer?.cancel();
    _expiryTimer = null;
    _tickTimer = null;
  }

  /// Calculates how much time is left and arms the appropriate timers.
  void _initTimer() {
    final requestedAt = widget.data['requestedAt'] as Timestamp?;
    if (requestedAt == null) {
      // No timestamp → treat as expired immediately
      setState(() {
        _expired = true;
        _remaining = Duration.zero;
      });
      _doExpire();
      return;
    }

    final elapsed = DateTime.now().difference(requestedAt.toDate());

    if (elapsed >= _kRequestExpiry) {
      // Already past the window when the card was first built
      setState(() {
        _expired = true;
        _remaining = Duration.zero;
      });
      _doExpire();
      return;
    }

    // Still within the window — calculate precise remaining duration
    final remaining = _kRequestExpiry - elapsed;
    setState(() {
      _remaining = remaining;
      _expired = false;
    });

    // ── One-shot expiry timer ─────────────────────────────────────────────
    _expiryTimer = Timer(remaining, () {
      if (!mounted) return;
      setState(() {
        _expired = true;
        _remaining = Duration.zero;
      });
      _doExpire();
    });

    // ── Countdown ticker: updates display every second ────────────────────
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final newElapsed = DateTime.now().difference(requestedAt.toDate());
      final newRemaining = _kRequestExpiry - newElapsed;
      if (newRemaining.isNegative || newRemaining == Duration.zero) {
        _tickTimer?.cancel();
        setState(() {
          _remaining = Duration.zero;
          _expired = true;
        });
      } else {
        setState(() => _remaining = newRemaining);
      }
    });
  }

  /// Calls the parent's expiry callback exactly once, then writes to Firestore.
  void _doExpire() {
    if (_expiryCalled) return;
    _expiryCalled = true;
    final travelerId =
        widget.data['travelerId'] as String? ?? widget.currentUserId;
    widget.onExpire(widget.docId, travelerId);
  }

  Future<void> _handle(bool accept) async {
    _cancelTimers(); // stop the timer before the async action
    setState(() => _handling = true);
    await widget.onHandle(widget.docId, accept);
    if (mounted) setState(() => _handling = false);
  }

  /// Formats remaining duration as "14 min 32 sec" or "45 sec"
  String get _countdownLabel {
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds % 60;
    if (m > 0) return '$m min ${s.toString().padLeft(2, '0')} sec';
    return '${s}s left';
  }

  /// Formats elapsed time as "Requested 3 minutes ago"
  String _timeAgo(Timestamp? ts) {
    if (ts == null) return 'Unknown time';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inSeconds < 60) return 'Requested just now';
    if (diff.inMinutes < 60) {
      return 'Requested ${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    return 'Requested ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }

  // ── Countdown colour (green → orange → red as time runs out) ─────────────
  Color get _countdownColor {
    final fraction = _remaining.inSeconds / _kRequestExpiry.inSeconds;
    if (fraction > 0.5) return _teal;
    if (fraction > 0.25) return _orange;
    return _red;
  }

  @override
  Widget build(BuildContext context) {
    final requestedAt = widget.data['requestedAt'] as Timestamp?;

    return GestureDetector(
      onTap: () => context.push('/traveler-parcel-details/${widget.docId}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _expired ? _red.withOpacity(0.03) : _orange.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _expired ? _red.withOpacity(0.25) : _orange.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Route + category row ───────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _expired
                        ? _red.withOpacity(0.1)
                        : _orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _expired
                        ? Icons.timer_off_outlined
                        : Icons.pending_actions_rounded,
                    color: _expired ? _red : _orange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.data['fromCity']} → ${widget.data['toCity']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _text1,
                        ),
                      ),
                      Text(
                        '${widget.data['category'] ?? 'Parcel'}  •  '
                        '₹${widget.data['price'] ?? 0}',
                        style: const TextStyle(fontSize: 12, color: _text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── "Requested X min ago" ──────────────────────────────────────
            if (requestedAt != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 12,
                    color: _expired ? _red : _text2,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _timeAgo(requestedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: _expired ? _red : _text2,
                      fontWeight: _expired
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],

            // ── Live countdown bar (hidden once expired) ───────────────────
            if (!_expired && _remaining.inSeconds > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 13,
                    color: _countdownColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _countdownLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _countdownColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'to respond',
                    style: TextStyle(
                      fontSize: 11,
                      color: _countdownColor.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_remaining.inSeconds / _kRequestExpiry.inSeconds)
                      .clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: _countdownColor.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(_countdownColor),
                ),
              ),
            ],

            // ── Expired warning banner ─────────────────────────────────────
            if (_expired) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _red.withOpacity(0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: _red),
                    SizedBox(width: 6),
                    Text(
                      'This request has expired.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ── Reject / Accept buttons ────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: _handling ? null : () => _handle(false),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text(
                        'Reject',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _red,
                        side: BorderSide(color: _red.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      // Disabled if expired OR already handling
                      onPressed: (_handling || _expired)
                          ? null
                          : () => _handle(true),
                      icon: _handling
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        _expired ? 'Expired' : 'Accept',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _expired ? _text2 : _green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _text2.withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  DELIVERIES TAB (unchanged)
// ════════════════════════════════════════════════════════════════════════════
class _DeliveriesTab extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  final Future<void> Function(String, String) onUpdateStatus;
  const _DeliveriesTab({required this.stream, required this.onUpdateStatus});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: _Appbar(title: 'My Deliveries'),
    body: StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _indigo));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _Empty(
            emoji: '🚌',
            label: 'No active deliveries',
            sub: 'Accept parcels from Home to start earning!',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snap.data!.docs.length,
          itemBuilder: (_, i) {
            final doc = snap.data!.docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _ActiveTile(
              data: data,
              docId: doc.id,
              onUpdateStatus: onUpdateStatus,
            );
          },
        );
      },
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  WALLET TAB (unchanged)
// ════════════════════════════════════════════════════════════════════════════
class _WalletTab extends StatelessWidget {
  final Stream<QuerySnapshot> completedStream;
  const _WalletTab({required this.completedStream});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: _Appbar(title: 'Wallet'),
    body: StreamBuilder<QuerySnapshot>(
      stream: completedStream,
      builder: (_, snap) {
        double total = 0, weekly = 0;
        final now = DateTime.now();
        final docs = snap.data?.docs ?? [];
        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final p = (d['price'] as num?)?.toDouble() ?? 0;
          total += p;
          final ts = d['createdAt'] as Timestamp?;
          if (ts != null && now.difference(ts.toDate()).inDays <= 7)
            weekly += p;
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_teal, Color(0xFF0D9488)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: _teal.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Earnings',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _WStat(
                        label: 'This Week',
                        value: '₹${weekly.toStringAsFixed(0)}',
                      ),
                      const SizedBox(width: 28),
                      _WStat(label: 'Deliveries', value: '${docs.length}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Recent Deliveries',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _text1,
              ),
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              _InfoCard(
                icon: '💰',
                text: 'Complete deliveries to see earnings here.',
                color: _text2,
              )
            else
              ...docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.check_circle_outline_rounded,
                          color: _green,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  d['fromCity'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _text1,
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 11,
                                    color: _text2,
                                  ),
                                ),
                                Text(
                                  d['toCity'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _text1,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              d['category'] ?? d['description'] ?? 'Parcel',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '+ ₹${d['price'] ?? 0}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _green,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  ROUTES TAB (unchanged)
// ════════════════════════════════════════════════════════════════════════════
class _RoutesTab extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  const _RoutesTab({required this.stream});

  String _formatDateTime(Timestamp? ts) {
    if (ts == null) return 'Not set';
    return DateFormat('dd MMM yyyy · hh:mm a').format(ts.toDate());
  }

  bool _isActive(Map<String, dynamic> data) {
    final storedStatus = data['status'] as String?;
    if (storedStatus != null) return storedStatus == 'active';
    final ts = data['travelDateTime'] as Timestamp?;
    if (ts == null) return false;
    return ts.toDate().isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _Appbar(title: 'My Routes'),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _indigo),
            );
          }
          if (snap.hasError) {
            return _InfoCard(
              icon: '⚠️',
              text: 'Could not load routes.\n${snap.error}',
              color: _red,
            );
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return _Empty(
              emoji: '🗺️',
              label: 'No routes added yet',
              sub:
                  'Tap "Add Route" on the Home tab to start sharing your travels.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snap.data!.docs.length,
            itemBuilder: (_, i) {
              final doc = snap.data!.docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final travelTs = data['travelDateTime'] as Timestamp?;
              final active = _isActive(data);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active
                        ? _teal.withOpacity(0.3)
                        : _text2.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: active
                            ? _teal.withOpacity(0.1)
                            : _text2.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        active ? Icons.route_rounded : Icons.route_outlined,
                        color: active ? _teal : _text2,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                data['fromCity'] ?? '',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: _text1,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 12,
                                  color: _text2,
                                ),
                              ),
                              Text(
                                data['toCity'] ?? '',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: _text1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(travelTs),
                            style: const TextStyle(fontSize: 12, color: _text2),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Bag space: ${data['bagSpaceKg'] ?? 0} kg',
                            style: const TextStyle(fontSize: 12, color: _text2),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? _teal.withOpacity(0.1)
                            : _text2.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        active ? 'ACTIVE' : 'INACTIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: active ? _teal : _text2,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PROFILE TAB (unchanged)
// ════════════════════════════════════════════════════════════════════════════
class _ProfileTab extends StatelessWidget {
  final User? user;
  final bool kycVerified, locationGranted;
  final VoidCallback onSetupTap, onSignOut, onSwitchSender;
  const _ProfileTab({
    required this.user,
    required this.kycVerified,
    required this.locationGranted,
    required this.onSetupTap,
    required this.onSignOut,
    required this.onSwitchSender,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: _Appbar(title: 'Profile'),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: _indigo.withOpacity(0.12),
                backgroundImage: user?.photoURL != null
                    ? NetworkImage(user!.photoURL!)
                    : null,
                child: user?.photoURL == null
                    ? Text(
                        (user?.displayName ?? 'T')[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _indigo,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'Traveler',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _text1,
                      ),
                    ),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(fontSize: 12, color: _text2),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _PBadge(
                          label: kycVerified ? '✅ KYC Done' : '⚠️ KYC Pending',
                          color: kycVerified ? _green : _orange,
                        ),
                        const SizedBox(width: 6),
                        _PBadge(
                          label: locationGranted ? '📍 GPS On' : '📍 GPS Off',
                          color: locationGranted ? _teal : _red,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _CheckRow(
                label: 'Location Access',
                done: locationGranted,
                onTap: onSetupTap,
              ),
              const Divider(color: Color(0xFFF1F5F9), height: 1),
              _CheckRow(
                label: 'KYC Document Uploaded',
                done: kycVerified,
                onTap: onSetupTap,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _MenuTile(
          icon: Icons.swap_horiz_rounded,
          color: _teal,
          label: 'Switch to Sender',
          onTap: onSwitchSender,
        ),
        _MenuTile(
          icon: Icons.help_outline_rounded,
          color: _indigo,
          label: 'Help & Support',
          onTap: () {},
        ),
        _MenuTile(
          icon: Icons.logout_rounded,
          color: _red,
          label: 'Sign Out',
          onTap: onSignOut,
          textColor: _red,
        ),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  REUSABLE WIDGETS (unchanged)
// ════════════════════════════════════════════════════════════════════════════
class _Appbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _Appbar({required this.title});
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: _indigo,
    elevation: 0,
    automaticallyImplyLeading: false,
    title: Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
    ),
  );
}

class _BottomNav extends StatelessWidget {
  final int index;
  final void Function(int) onTap;
  const _BottomNav({required this.index, required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.07),
          blurRadius: 20,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: BottomNavigationBar(
      currentIndex: index,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: _indigo,
      unselectedItemColor: _text2,
      backgroundColor: Colors.white,
      elevation: 0,
      selectedFontSize: 11,
      unselectedFontSize: 11,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.local_shipping_outlined),
          activeIcon: Icon(Icons.local_shipping_rounded),
          label: 'Deliveries',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet_outlined),
          activeIcon: Icon(Icons.account_balance_wallet_rounded),
          label: 'Wallet',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.route_outlined),
          activeIcon: Icon(Icons.route_rounded),
          label: 'Routes',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline_rounded),
          activeIcon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    ),
  );
}

class _PickerField extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool hasValue;
  const _PickerField({
    required this.icon,
    required this.text,
    required this.hasValue,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: _text2),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: hasValue ? _text1 : _text2),
          ),
        ),
        const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _text2),
      ],
    ),
  );
}

class _SetupBanner extends StatelessWidget {
  final bool locationGranted, kycVerified;
  final VoidCallback onTap;
  const _SetupBanner({
    required this.locationGranted,
    required this.kycVerified,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final steps = [
      if (!locationGranted) '📍 Allow Location',
      if (!kycVerified) '🪪 Upload KYC',
    ];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _orange.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: _orange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Complete setup to accept parcels',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    steps.join('  •  '),
                    style: const TextStyle(fontSize: 11, color: _orange),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: _orange,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddRouteCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddRouteCard({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _indigo.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Your Travel Route',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Planning to travel? Carry parcels and earn.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_road_rounded, color: _indigo, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Add Route',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _indigo,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Text('🗺️', style: TextStyle(fontSize: 50)),
        ],
      ),
    ),
  );
}

class _EarningCard extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  const _EarningCard({required this.stream});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
    stream: stream,
    builder: (_, snap) {
      double total = 0, weekly = 0;
      final now = DateTime.now();
      for (final doc in snap.data?.docs ?? []) {
        final d = doc.data() as Map<String, dynamic>;
        final p = (d['price'] as num?)?.toDouble() ?? 0;
        total += p;
        final ts = d['createdAt'] as Timestamp?;
        if (ts != null && now.difference(ts.toDate()).inDays <= 7) weekly += p;
      }
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _teal.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: _teal,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Earnings Summary',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _text1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(color: Color(0xFFF1F5F9), height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ETile(
                    label: 'Total Earned',
                    value: '₹${total.toStringAsFixed(0)}',
                    icon: Icons.bar_chart_rounded,
                    color: _indigo,
                  ),
                ),
                Container(width: 1, height: 56, color: const Color(0xFFF1F5F9)),
                Expanded(
                  child: _ETile(
                    label: 'This Week',
                    value: '₹${weekly.toStringAsFixed(0)}',
                    icon: Icons.trending_up_rounded,
                    color: _teal,
                  ),
                ),
                Container(width: 1, height: 56, color: const Color(0xFFF1F5F9)),
                Expanded(
                  child: _ETile(
                    label: 'Deliveries',
                    value: '${snap.data?.docs.length ?? 0}',
                    icon: Icons.local_shipping_outlined,
                    color: _orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _ETile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _ETile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 5),
      Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: _text2),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _ActiveSection extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  final Future<void> Function(String, String) onUpdateStatus;
  const _ActiveSection({required this.stream, required this.onUpdateStatus});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
    stream: stream,
    builder: (_, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const SizedBox(
          height: 50,
          child: Center(child: CircularProgressIndicator(color: _indigo)),
        );
      }
      if (!snap.hasData || snap.data!.docs.isEmpty) {
        return _InfoCard(
          icon: '🚌',
          text: 'No active deliveries yet. Accept a parcel to start!',
          color: _text2,
        );
      }
      return Column(
        children: snap.data!.docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return _ActiveTile(
            data: d,
            docId: doc.id,
            onUpdateStatus: onUpdateStatus,
          );
        }).toList(),
      );
    },
  );
}

class _ActiveTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final Future<void> Function(String, String) onUpdateStatus;
  const _ActiveTile({
    required this.data,
    required this.docId,
    required this.onUpdateStatus,
  });

  Color get _sc => data['status'] == 'accepted' ? _indigo : _orange;
  String get _nextStatus =>
      data['status'] == 'accepted' ? 'picked' : 'delivered';
  String get _nextLabel =>
      data['status'] == 'accepted' ? 'Mark Picked' : 'Mark Delivered';

  @override
  Widget build(BuildContext context) {
    final double price = (data['price'] ?? 0).toDouble();
    final double travelerEarn = price * 0.70;
    return InkWell(
      onTap: () => context.push('/traveler-parcel-details/$docId'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _sc.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: _sc.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _sc.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                data['status'] == 'accepted'
                    ? Icons.inventory_2_outlined
                    : Icons.local_shipping_outlined,
                color: _sc,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        data['fromCity'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _text1,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 12,
                          color: _text2,
                        ),
                      ),
                      Text(
                        data['toCity'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _text1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Earn ₹${travelerEarn.toStringAsFixed(0)}  •  '
                    '${(data['status'] ?? '').toString().toUpperCase()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _sc,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => onUpdateStatus(docId, _nextStatus),
              style: TextButton.styleFrom(
                foregroundColor: _sc,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: _sc.withOpacity(0.4)),
                ),
              ),
              child: Text(
                _nextLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────
class _StepTile extends StatelessWidget {
  final String stepNum, title, subtitle, buttonLabel;
  final IconData icon;
  final Color color;
  final bool done;
  final Future<void> Function()? onTap;
  const _StepTile({
    required this.stepNum,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.buttonLabel,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: done ? _green.withOpacity(0.04) : color.withOpacity(0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: done ? _green.withOpacity(0.25) : color.withOpacity(0.2),
      ),
    ),
    child: Row(
      children: [
        _StepCircle(num: stepNum, done: done),
        const SizedBox(width: 10),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (done ? _green : color).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            done ? Icons.check_circle_rounded : icon,
            color: done ? _green : color,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: done ? _green : _text1,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: _text2),
              ),
            ],
          ),
        ),
        if (!done && onTap != null)
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: color.withOpacity(0.4)),
              ),
            ),
            child: Text(
              buttonLabel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    ),
  );
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: Colors.grey[300],
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class _StepCircle extends StatelessWidget {
  final String num;
  final bool done;
  const _StepCircle({required this.num, required this.done});
  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: done ? _green : _indigo,
      shape: BoxShape.circle,
    ),
    child: Center(
      child: done
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : Text(
              num,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
    ),
  );
}

class _HBadge extends StatelessWidget {
  final String label;
  final Color bg;
  const _HBadge({required this.label, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
  );
}

class _QStat extends StatelessWidget {
  final String label, value;
  const _QStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  final String icon, title;
  const _SectionTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(icon, style: const TextStyle(fontSize: 18)),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: _text1,
        ),
      ),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  final String icon, text;
  final Color color;
  const _InfoCard({
    required this.icon,
    required this.text,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: color, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  final String emoji, label, sub;
  const _Empty({required this.emoji, required this.label, required this.sub});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _text1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _text2, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

class _PBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _PBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool done;
  final VoidCallback onTap;
  const _CheckRow({
    required this.label,
    required this.done,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
      color: done ? _green : _text2,
      size: 20,
    ),
    title: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        color: done ? _text1 : _text2,
        fontWeight: done ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
    trailing: done
        ? null
        : TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: _indigo,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Complete →',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
  );
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final Color? textColor;
  const _MenuTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.textColor,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textColor ?? _text1,
        ),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 13,
        color: _text2,
      ),
      onTap: onTap,
    ),
  );
}

class _WStat extends StatelessWidget {
  final String label, value;
  const _WStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    ],
  );
}

class _SourceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: _indigo),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _text1,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _SheetDropdown extends StatelessWidget {
  final String label, value;
  final List<String> items;
  final void Function(String?) onChanged;
  const _SheetDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _text2,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: _text2,
            ),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _text1,
            ),
            items: items
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    ],
  );
}

class _SheetField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  const _SheetField({
    required this.ctrl,
    required this.hint,
    required this.icon,
    this.keyboardType,
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: _text2),
      filled: true,
      fillColor: const Color(0xFFF8FAFF),
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFAAAAAA)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _indigo, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    ),
  );
}
