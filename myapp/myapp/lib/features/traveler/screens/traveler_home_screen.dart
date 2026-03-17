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
import 'package:myapp/features/auth/screens/login_signup_screen.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;
import 'package:intl/intl.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:myapp/notifications/notifications.dart';

// Import the new wallet screen
import '../../../screens/wallet_screen.dart';

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

/// How long a traveler has to respond before the request auto‑expires.
const _kRequestExpiry = Duration(minutes: 15);

const Map<String, List<String>> cityAreas = {
  "Nashik": ["Panchavati", "Satpur", "Indira Nagar", "Gangapur Road"],
  "Pune": ["Kothrud", "Baner", "Hinjewadi", "Wakad", "Shivajinagar"],
  "Mumbai": ["Andheri", "Bandra", "Borivali", "Dadar", "Powai"],
  "Aurangabad": ["CIDCO", "Garkheda", "Satara"],
  "Nagpur": ["Dharampeth", "Sitabuldi", "Manish Nagar"],
};

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
  bool _loading = true;

  // Stream subscription for user doc changes
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  @override
  void initState() {
    super.initState();
    _listenToUserChanges();
  }

  void _listenToUserChanges() {
    final uid = _user?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final data = snapshot.data() ?? {};
            setState(() {
              _kycVerified = data['kycVerified'] == true;
              _loading = false;
            });
          },
          onError: (e) {
            debugPrint('Error listening to user: $e');
            setState(() => _loading = false);
          },
        );
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  /// Checks location services and permission.
  /// Returns true if location is available, otherwise shows a message.
  Future<bool> _checkLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _toast(
        '📍 Please enable location / GPS in your device settings.',
        isError: true,
      );
      await Geolocator.openLocationSettings();
      return false;
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      if (requested == LocationPermission.denied) {
        _toast('Location permission denied.', isError: true);
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _toast(
        'Location blocked. Open Settings and allow location for Saarthi.',
        isError: true,
      );
      await openAppSettings();
      return false;
    }
    return true;
  }

  /// Checks KYC verification and shows a message if not verified.
  bool _checkKyc() {
    if (!_kycVerified) {
      _toast(
        'Your KYC is under review or you dont submitted kyc request. You cannot perform this action until verification is approved.',
        isError: true,
      );
      return false;
    }
    return true;
  }

  /// Combined check for actions that require both location and KYC.
  Future<bool> _checkLocationAndKyc() async {
    if (!_checkKyc()) return false;
    return await _checkLocation();
  }

  Future<void> _updateDeliveryStatus(String parcelId, String newStatus) async {
    final parcelRef = FirebaseFirestore.instance
        .collection('parcels')
        .doc(parcelId);

    await parcelRef.update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (newStatus == 'delivered') {
      final parcelSnap = await parcelRef.get();
      final data = parcelSnap.data();

      final travelerId = data?['travelerId'];
      final fromCity = data?['fromCity'];
      final toCity = data?['toCity'];

      final routeQuery = await FirebaseFirestore.instance
          .collection('travelRoutes')
          .where('travelerId', isEqualTo: travelerId)
          .where('fromCity', isEqualTo: fromCity)
          .where('toCity', isEqualTo: toCity)
          .limit(1)
          .get();

      if (routeQuery.docs.isNotEmpty) {
        await routeQuery.docs.first.reference.update({'status': 'inactive'});
      }

      await _addEarningsToWallet(parcelId);
    }
  }

  Future<void> _addEarningsToWallet(String parcelId) async {
    try {
      final parcelSnap = await FirebaseFirestore.instance
          .collection('parcels')
          .doc(parcelId)
          .get();
      if (!parcelSnap.exists) return;
      final data = parcelSnap.data()!;
      final price = (data['price'] as num?)?.toDouble() ?? 0;
      final travelerId = data['travelerId'] as String?;
      if (travelerId == null) return;

      final earned = price * 0.70; // 70% to traveler

      await FirebaseFirestore.instance
          .collection('wallets')
          .doc(travelerId)
          .set({
            'balance': FieldValue.increment(earned),
            'totalEarnings': FieldValue.increment(earned),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('_addEarningsToWallet error: $e');
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
    await googleSignIn.signOut();
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
        kycVerified: _kycVerified,
        onKycSubmitted: () {
          _toast(
            '📄 KYC submitted! Please wait for admin approval. You will be notified once verified.',
          );
        },
      ),
    );
  }

  void _showAddRouteSheet() async {
    // Check KYC and location before opening the sheet.
    if (!await _checkLocationAndKyc()) return;

    // Local state for the sheet
    String fromCity = 'Nashik', toCity = 'Pune';
    String fromArea = '', toArea = '';
    final fromAddressCtrl = TextEditingController();
    final toAddressCtrl = TextEditingController();
    double? fromLat, fromLon, toLat, toLon;
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    final spaceCtrl = TextEditingController();
    const routeCities = ['Nashik', 'Pune', 'Mumbai', 'Aurangabad', 'Nagpur'];

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
          builder: (ctx, setSheetState) => SingleChildScrollView(
            child: Column(
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

                // FROM section
                const Text(
                  'From',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _text2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _SheetDropdown(
                        label: 'City',
                        value: fromCity,
                        items: routeCities,
                        onChanged: (val) {
                          setSheetState(() {
                            fromCity = val!;
                            fromArea = ''; // reset area
                            fromAddressCtrl.clear();
                            fromLat = fromLon = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SheetDropdown(
                        label: 'Area',
                        value: fromArea.isEmpty ? null : fromArea,
                        items: cityAreas[fromCity] ?? [],
                        onChanged: (val) =>
                            setSheetState(() => fromArea = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // From address autocomplete (only shown if area selected)
                if (fromArea.isNotEmpty) ...[
                  AddressAutocompleteField(
                    controller: fromAddressCtrl,
                    city: fromCity,
                    area: fromArea,
                    hintText: 'Search pickup address (optional)',
                    prefixIcon: Icons.location_on_outlined,
                    onSelected: (address, lat, lng) {
                      setSheetState(() {
                        fromAddressCtrl.text = address;
                        fromLat = lat;
                        fromLon = lng;
                      });
                    },
                  ),
                  if (fromLat != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: _green, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Coordinates set',
                            style: TextStyle(color: _green, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                ],

                const SizedBox(height: 16),

                // TO section
                const Text(
                  'To',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _text2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _SheetDropdown(
                        label: 'City',
                        value: toCity,
                        items: routeCities,
                        onChanged: (val) {
                          setSheetState(() {
                            toCity = val!;
                            toArea = '';
                            toAddressCtrl.clear();
                            toLat = toLon = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SheetDropdown(
                        label: 'Area',
                        value: toArea.isEmpty ? null : toArea,
                        items: cityAreas[toCity] ?? [],
                        onChanged: (val) => setSheetState(() => toArea = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // To address autocomplete
                if (toArea.isNotEmpty) ...[
                  AddressAutocompleteField(
                    controller: toAddressCtrl,
                    city: toCity,
                    area: toArea,
                    hintText: 'Search drop address (optional)',
                    prefixIcon: Icons.location_on_outlined,
                    onSelected: (address, lat, lng) {
                      setSheetState(() {
                        toAddressCtrl.text = address;
                        toLat = lat;
                        toLon = lng;
                      });
                    },
                  ),
                  if (toLat != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: _green, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Coordinates set',
                            style: TextStyle(color: _green, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                ],

                const SizedBox(height: 16),

                // Date & Time
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setSheetState(() => selectedDate = picked);
                    }
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
                    if (picked != null) {
                      setSheetState(() => selectedTime = picked);
                    }
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

                // Bag space
                _SheetField(
                  ctrl: spaceCtrl,
                  hint: 'Available bag space (kg)',
                  icon: Icons.luggage_outlined,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),

                // Save button
                _PrimaryBtn(
                  label: 'Save Route',
                  onTap: () async {
                    final uid = _user?.uid;
                    if (uid == null) return;

                    // Basic validation
                    if (fromCity.isEmpty || toCity.isEmpty) {
                      _toast('Please select from/to city', isError: true);
                      return;
                    }
                    if (fromArea.isEmpty || toArea.isEmpty) {
                      _toast('Please select from/to area', isError: true);
                      return;
                    }
                    if (selectedDate == null || selectedTime == null) {
                      _toast('Please select both date and time', isError: true);
                      return;
                    }
                    final bagSpace = double.tryParse(spaceCtrl.text);
                    if (bagSpace == null || bagSpace <= 0) {
                      _toast(
                        'Please enter valid bag space (>0)',
                        isError: true,
                      );
                      return;
                    }

                    final travelDateTime = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedTime!.hour,
                      selectedTime!.minute,
                    );

                    // Prepare data
                    final routeData = {
                      'travelerId': uid,
                      'travelerName': _user?.displayName ?? '',
                      'fromCity': fromCity,
                      'fromArea': fromArea,
                      'toCity': toCity,
                      'toArea': toArea,
                      'address': fromAddressCtrl.text,
                      'latitude': fromLat,
                      'longitude': fromLon,
                      'travelDateTime': Timestamp.fromDate(travelDateTime),
                      'bagSpaceKg': bagSpace,
                      'status': 'active',
                      'createdAt': FieldValue.serverTimestamp(),
                    };

                    try {
                      await FirebaseFirestore.instance
                          .collection('travelRoutes')
                          .add(routeData);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _toast(
                        '🗺️ Route saved! You\'ll be matched with parcels.',
                      );
                    } catch (e) {
                      _toast('Failed to save route: $e', isError: true);
                    }
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HANDLE INCOMING REQUESTS
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _handleRequest(String parcelId, bool accept) async {
    // Check location and KYC before allowing accept/reject.
    if (accept) {
      if (!await _checkLocationAndKyc()) return;
    } else {
      // Rejecting might not require location, but still KYC? Let's require both for consistency.
      if (!await _checkLocationAndKyc()) return;
    }

    try {
      if (accept) {
        final parcelSnap = await FirebaseFirestore.instance
            .collection('parcels')
            .doc(parcelId)
            .get();

        if (!parcelSnap.exists) {
          _toast('Parcel not found', isError: true);
          return;
        }

        final parcelData = parcelSnap.data()!;

        final senderId = parcelData['senderId'];
        final fromCity = parcelData['fromCity'];
        final toCity = parcelData['toCity'];
        final travelerName =
            FirebaseAuth.instance.currentUser?.displayName ?? 'Traveler';

        await FirebaseFirestore.instance
            .collection('parcels')
            .doc(parcelId)
            .update({
              'status': 'accepted',
              'acceptedAt': FieldValue.serverTimestamp(),
            });

        _toast('✅ Request accepted. Contact sender for pickup.');

        // Send notification to sender
        await NotificationService.notifyParcelAccepted(
          toUid: senderId,
          parcelId: parcelId,
          travelerName: travelerName,
          fromCity: fromCity,
          toCity: toCity,
        );
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
        incomingStream: _incomingRequests,
        activeStream: _myDeliveries,
        completedStream: _completedDeliveries,
        onHandleRequest: _handleRequest,
        onExpireRequest: _expireRequest,
        onUpdateStatus: _updateDeliveryStatus,
        onAddRouteTap: _showAddRouteSheet,
        onSetupTap: _showSetupSheet,
        onCheckLocation: _checkLocation,
      ),
      _DeliveriesTab(
        stream: _myDeliveries,
        onUpdateStatus: _updateDeliveryStatus,
      ),
      // New Wallet Screen
      WalletScreen(
        userId: _user?.uid ?? '',
        userName: _user?.displayName ?? 'Traveler',
      ),
      _RoutesTab(stream: _myRoutes),
      _ProfileTab(
        user: _user,
        kycVerified: _kycVerified,
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
//  SETUP SHEET (extended KYC form with selfie)
// ════════════════════════════════════════════════════════════════════════════
class _SetupSheet extends StatefulWidget {
  final String uid;
  final bool kycVerified;
  final VoidCallback onKycSubmitted;
  const _SetupSheet({
    required this.uid,
    required this.kycVerified,
    required this.onKycSubmitted,
  });
  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  // KYC fields
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();

  File? _docFile;
  File? _selfieFile;
  bool _uploading = false;
  String _docType = 'Aadhaar Card';
  static const _docTypes = [
    'Aadhaar Card',
    'PAN Card',
    'Voter ID',
    'Driving Licence',
    'Passport',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill email and name from Firebase if available
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _fullNameController.text = user.displayName ?? '';
      _emailController.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// Permission handling for camera/gallery.
  Future<bool> _requestPermission(ImageSource source) async {
    PermissionStatus status;
    if (source == ImageSource.camera) {
      status = await Permission.camera.request();
    } else {
      // Gallery: platform‑specific
      status = await Permission.photos.request();
    }
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Permission permanently denied. Please enable in settings.',
            ),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await openAppSettings();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission denied.'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    return false;
  }

  Future<void> _pickImage(ImageSource source, bool isSelfie) async {
    if (!await _requestPermission(source)) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1400,
    );
    if (picked != null) {
      setState(() {
        if (isSelfie) {
          _selfieFile = File(picked.path);
        } else {
          _docFile = File(picked.path);
        }
      });
    }
  }

  Future<void> _submitKyc() async {
    // Validate all fields
    if (_fullNameController.text.trim().isEmpty) {
      _showError('Please enter your full name.');
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      _showError('Please enter your email.');
      return;
    }
    if (_dobController.text.trim().isEmpty) {
      _showError('Please select your date of birth.');
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _showError('Please enter your address.');
      return;
    }
    if (_docFile == null) {
      _showError('Please upload a government document photo.');
      return;
    }
    if (_selfieFile == null) {
      _showError('Please capture a live selfie using the camera.');
      return;
    }

    setState(() => _uploading = true);

    try {
      // Upload document image
      final docUrl = await _uploadToCloudinary(_docFile!, 'kyc_docs');
      // Upload selfie image
      final selfieUrl = await _uploadToCloudinary(_selfieFile!, 'kyc_selfies');

      // Create KYC request document
      await FirebaseFirestore.instance
          .collection('kycRequests')
          .doc(widget.uid)
          .set({
            'uid': widget.uid,
            'fullName': _fullNameController.text.trim(),
            'email': _emailController.text.trim(),
            'dateOfBirth': _dobController.text.trim(),
            'address': _addressController.text.trim(),
            'documentType': _docType,
            'documentUrl': docUrl,
            'selfieUrl': selfieUrl,
            'status': 'requested',
            'submittedAt': FieldValue.serverTimestamp(),
          });

      // Do NOT set kycVerified in users collection.
      widget.onKycSubmitted();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<String> _uploadToCloudinary(File file, String folder) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = folder
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: '${folder}_${widget.uid}.jpg',
        ),
      );
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception(
        'Cloudinary error ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['secure_url'] as String;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSourcePicker(bool isSelfie) {
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
                      _pickImage(ImageSource.camera, isSelfie);
                    },
                  ),
                ),
                if (!isSelfie) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceCard(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery, isSelfie);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kycVerified) {
      // If already verified, show a simple message.
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Handle(),
            const SizedBox(height: 20),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: _green.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: _green,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'KYC Already Verified',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _green,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your identity has been verified. You can now accept parcels and create routes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _text2),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      );
    }

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
              child: const Icon(Icons.badge_outlined, color: _indigo, size: 28),
            ),
            const SizedBox(height: 12),
            const Text(
              'KYC Verification',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _text1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please fill in your details and upload the required documents. '
              'Your submission will be reviewed by an admin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _text2),
            ),
            const SizedBox(height: 24),

            // Personal details
            _buildTextField(
              controller: _fullNameController,
              label: 'Full Name',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _emailController,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _dobController.text = DateFormat('yyyy-MM-dd').format(picked);
                }
              },
              child: _buildReadOnlyField(
                controller: _dobController,
                label: 'Date of Birth',
                icon: Icons.calendar_today_outlined,
              ),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _addressController,
              label: 'Address',
              icon: Icons.location_on_outlined,
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Document type dropdown
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
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _docType = v!),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Document upload
            _buildImagePicker(
              file: _docFile,
              label: 'Government Document',
              isSelfie: false,
            ),
            const SizedBox(height: 12),

            // Selfie capture
            _buildImagePicker(
              file: _selfieFile,
              label: 'Live Selfie (Camera only)',
              isSelfie: true,
            ),
            const SizedBox(height: 12),

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
                      'Your documents are encrypted and stored securely. '
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
            const SizedBox(height: 16),

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
                          Text('Uploading…', style: TextStyle(fontSize: 14)),
                        ],
                      )
                    : const Text(
                        'Submit KYC for Review',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: _text2),
        filled: true,
        fillColor: const Color(0xFFF8FAFF),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
      ),
    );
  }

  Widget _buildReadOnlyField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
              controller.text.isEmpty ? label : controller.text,
              style: TextStyle(
                fontSize: 14,
                color: controller.text.isEmpty ? _text2 : _text1,
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: _text2,
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker({
    required File? file,
    required String label,
    required bool isSelfie,
  }) {
    return GestureDetector(
      onTap: () => _showSourcePicker(isSelfie),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: file != null ? 150 : 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: file != null
                ? _indigo.withOpacity(0.5)
                : const Color(0xFFCBD5E1),
            width: file != null ? 1.5 : 1,
          ),
        ),
        child: file != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.file(file, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _showSourcePicker(isSelfie),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
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
                    child: Icon(
                      isSelfie
                          ? Icons.camera_alt_outlined
                          : Icons.upload_file_outlined,
                      color: _indigo,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _indigo,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSelfie ? 'Camera only' : 'Camera or Gallery • JPG/PNG',
                    style: const TextStyle(fontSize: 11, color: _text2),
                  ),
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
  final bool kycVerified;
  final Stream<QuerySnapshot> incomingStream;
  final Stream<QuerySnapshot> activeStream, completedStream;
  final Future<void> Function(String, bool) onHandleRequest;
  final Future<void> Function(String, String) onExpireRequest;
  final Future<void> Function(String, String) onUpdateStatus;
  final VoidCallback onAddRouteTap, onSetupTap;
  final Future<bool> Function() onCheckLocation;

  const _HomeTab({
    required this.user,
    required this.kycVerified,
    required this.incomingStream,
    required this.activeStream,
    required this.completedStream,
    required this.onHandleRequest,
    required this.onExpireRequest,
    required this.onUpdateStatus,
    required this.onAddRouteTap,
    required this.onSetupTap,
    required this.onCheckLocation,
  });

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

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
                              if (kycVerified)
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
                             StreamBuilder<DocumentSnapshot>(
  stream: FirebaseFirestore.instance
      .collection('users')
      .doc(user?.uid)
      .snapshots(),
  builder: (context, snapshot) {

    double rating = 0;

    if (snapshot.hasData && snapshot.data!.exists) {
      final data = snapshot.data!.data() as Map<String, dynamic>;
      rating = (data['rating'] ?? 0).toDouble();
    }

    return _HBadge(
      label: '⭐ ${rating.toStringAsFixed(1)} Rating',
      bg: Colors.white.withOpacity(0.18),
    );
  },
),
                              const SizedBox(height: 4),
                              _HBadge(
                                label: kycVerified
                                    ? '✅ Verified'
                                    : '⏳ KYC Pending',
                                bg: kycVerified
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
  final price = ((d.data() as Map)['price'] as num?)?.toDouble() ?? 0;
  total += price * 0.70;
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
                                value: kycVerified ? 'Active' : 'Pending',
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
                // KYC pending banner
                if (!kycVerified) ...[
                  _KycPendingBanner(onSetupTap: onSetupTap),
                  const SizedBox(height: 16),
                ],

                // Location disabled banner (real‑time check)
                StreamBuilder<ServiceStatus>(
                  stream: Geolocator.getServiceStatusStream(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData &&
                        snapshot.data == ServiceStatus.disabled) {
                      return _LocationDisabledBanner();
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 16),

                _AddRouteCard(onTap: onAddRouteTap),
                const SizedBox(height: 22),
                _EarningCard(userId: user?.uid ?? ''),
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

// Banner for KYC pending
class _KycPendingBanner extends StatelessWidget {
  final VoidCallback onSetupTap;
  const _KycPendingBanner({required this.onSetupTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSetupTap,
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
                Icons.access_time_rounded,
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
                    'KYC verification pending',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Please wait for admin approval.',
                    style: TextStyle(fontSize: 11, color: _orange),
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

// Banner for location disabled
class _LocationDisabledBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF0F0), Color(0xFFFFE0E0)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _red.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_off_rounded,
              color: _red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location services are off',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7F1D1D),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Please enable GPS to accept parcels.',
                  style: TextStyle(fontSize: 11, color: _red),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await Geolocator.openLocationSettings();
            },
            style: TextButton.styleFrom(
              foregroundColor: _red,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: _red.withOpacity(0.4)),
              ),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  REQUEST CARD (unchanged timer logic)
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
  Timer? _expiryTimer;
  Timer? _tickTimer;
  Duration _remaining = Duration.zero;
  bool _expired = false;
  bool _handling = false;
  bool _expiryCalled = false;

  @override
  void initState() {
    super.initState();
    _initTimer();
  }

  @override
  void didUpdateWidget(_RequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  void _initTimer() {
    final requestedAt = widget.data['requestedAt'] as Timestamp?;
    if (requestedAt == null) {
      setState(() {
        _expired = true;
        _remaining = Duration.zero;
      });
      _doExpire();
      return;
    }

    final elapsed = DateTime.now().difference(requestedAt.toDate());

    if (elapsed >= _kRequestExpiry) {
      setState(() {
        _expired = true;
        _remaining = Duration.zero;
      });
      _doExpire();
      return;
    }

    final remaining = _kRequestExpiry - elapsed;
    setState(() {
      _remaining = remaining;
      _expired = false;
    });

    _expiryTimer = Timer(remaining, () {
      if (!mounted) return;
      setState(() {
        _expired = true;
        _remaining = Duration.zero;
      });
      _doExpire();
    });

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

  void _doExpire() {
    if (_expiryCalled) return;
    _expiryCalled = true;
    final travelerId =
        widget.data['travelerId'] as String? ?? widget.currentUserId;
    widget.onExpire(widget.docId, travelerId);
  }

  Future<void> _handle(bool accept) async {
    _cancelTimers();
    setState(() => _handling = true);
    await widget.onHandle(widget.docId, accept);
    if (mounted) setState(() => _handling = false);
  }

  String get _countdownLabel {
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds % 60;
    if (m > 0) return '$m min ${s.toString().padLeft(2, '0')} sec';
    return '${s}s left';
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return 'Unknown time';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inSeconds < 60) return 'Requested just now';
    if (diff.inMinutes < 60) {
      return 'Requested ${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    return 'Requested ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }

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
//  DELIVERIES TAB
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
//  ROUTES TAB
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
//  PROFILE TAB
// ════════════════════════════════════════════════════════════════════════════
class _ProfileTab extends StatelessWidget {
  final User? user;
  final bool kycVerified;
  final VoidCallback onSetupTap, onSignOut, onSwitchSender;
  const _ProfileTab({
    required this.user,
    required this.kycVerified,
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
                    _PBadge(
                      label: kycVerified ? '✅ Verified' : '⏳ KYC Pending',
                      color: kycVerified ? _green : _orange,
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
                label: 'KYC Status',
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
  final String userId;
  const _EarningCard({required this.userId});
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance
        .collection('wallets')
        .doc(userId)
        .snapshots(),
    builder: (_, snap) {
      double total = 0;
      double balance = 0;
      double withdrawn = 0;

      if (snap.hasData && snap.data!.exists) {
        final data = snap.data!.data() as Map<String, dynamic>;

        total = (data['totalEarnings'] ?? 0).toDouble();
        balance = (data['balance'] ?? 0).toDouble();
        withdrawn = (data['totalWithdrawn'] ?? 0).toDouble();
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
                    label: 'Wallet Balance',
                    value: '₹${balance.toStringAsFixed(0)}',
                    icon: Icons.account_balance_wallet,
                    color: _teal,
                  ),
                ),
                Container(width: 1, height: 56, color: const Color(0xFFF1F5F9)),
                Expanded(
                  child: _ETile(
                    label: 'Withdrawn',
                    value: '₹${withdrawn.toStringAsFixed(0)}',
                    icon: Icons.payments_outlined,
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
  final String label;
  final String? value;
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

class AddressAutocompleteField extends StatelessWidget {
  final TextEditingController controller;
  final String city;
  final String area;
  final String hintText;
  final IconData prefixIcon;
  final Function(String, double, double) onSelected;

  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.city,
    required this.area,
    required this.onSelected,
    this.hintText = "Search address",
    this.prefixIcon = Icons.search,
  });

  Future<List<dynamic>> _search(String query) async {
    final url = Uri.parse(
      "https://nominatim.openstreetmap.org/search"
      "?q=${Uri.encodeComponent("$query $area $city")}"
      "&format=json"
      "&limit=5"
      '&countrycodes=in',
    );

    final res = await http.get(url, headers: {'User-Agent': 'SaarthiApp'});
    return jsonDecode(res.body);
  }

  @override
  Widget build(BuildContext context) {
    return TypeAheadField(
      controller: controller,
      builder: (context, controller, focusNode) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(prefixIcon),
          ),
        );
      },
      suggestionsCallback: (pattern) async {
        return await _search(pattern);
      },
      itemBuilder: (context, suggestion) {
        return ListTile(
          leading: const Icon(Icons.place),
          title: Text(suggestion["display_name"]),
        );
      },
      onSelected: (suggestion) {
        controller.text = suggestion["display_name"];
        onSelected(
          suggestion["display_name"],
          double.parse(suggestion["lat"]),
          double.parse(suggestion["lon"]),
        );
      },
    );
  }
}
