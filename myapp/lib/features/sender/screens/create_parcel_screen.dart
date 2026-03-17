import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart'; // <-- Added
import 'dart:math' as math;
// ---------- Color Palette ----------
const primaryColor = Color(0xFF4F46E5);
const secondaryColor = Color(0xFF14B8A6);
const accentColor = Color(0xFFF97316);
const backgroundColor = Color(0xFFF8FAFC);
const textPrimary = Color(0xFF0F172A);
const textSecondary = Color(0xFF64748B);
const cardBorder = Color(0xFFE2E8F0);

// ---------- Data Models ----------
class Location {
  String city;
  String area;
  String address;
  double? latitude;
  double? longitude;

  Location({
    this.city = '',
    this.area = '',
    this.address = '',
    this.latitude,
    this.longitude,
  });

  bool get isComplete =>
      city.isNotEmpty &&
      area.isNotEmpty &&
      address.isNotEmpty &&
      latitude != null &&
      longitude != null;

  Map<String, dynamic> toJson() => {
    'city': city,
    'area': area,
    'address': address,
    'lat': latitude,
    'lng': longitude,
  };
}

class ParcelSize {
  final String label;
  final double weightKg;
  final double price;
  const ParcelSize({
    required this.label,
    required this.weightKg,
    required this.price,
  });
}

class SubCategory {
  final String label;
  final String emoji;
  const SubCategory({required this.label, required this.emoji});
}

class MainCategory {
  final String label;
  final String emoji;
  final Color color;
  final IconData icon;
  final List<SubCategory> subCategories;
  final List<ParcelSize> sizes;
  final double pricePerKm; // ✅ added

  const MainCategory({
    required this.label,
    required this.emoji,
    required this.color,
    required this.icon,
    required this.subCategories,
    required this.sizes,
        required this.pricePerKm, // ✅ added

  });
}

// ---------- Categories ----------
final mainCategories = [
  MainCategory(
    label: 'Document',
    emoji: '📄',
    color: primaryColor,
    icon: Icons.description_outlined,
        pricePerKm: 2, 
    subCategories: const [
      SubCategory(label: 'Legal Papers', emoji: '⚖️'),
      SubCategory(label: 'Certificate', emoji: '🏅'),
      SubCategory(label: 'ID / Passport', emoji: '🪪'),
      SubCategory(label: 'Invoice / Bill', emoji: '🧾'),
      SubCategory(label: 'Academic Papers', emoji: '📚'),
      SubCategory(label: 'Other', emoji: '📋'),
    ],
    sizes: const [
      ParcelSize(label: 'A4 Envelope', weightKg: 0.2, price: 40),
      ParcelSize(label: 'File Folder', weightKg: 0.5, price: 70),
      ParcelSize(label: 'Document Bundle', weightKg: 1.0, price: 110),
    ],
  ),
  MainCategory(
    label: 'Food',
    emoji: '🍱',
    color: accentColor,
    icon: Icons.fastfood_outlined,
      pricePerKm: 3, // ₹6/km
    subCategories: const [
      SubCategory(label: 'Seasonal Items', emoji: '🌾'),
      SubCategory(label: 'Home-cooked Meal', emoji: '🍲'),
      SubCategory(label: 'Sweets / Mithai', emoji: '🍬'),
      SubCategory(label: 'Dry Fruits / Nuts', emoji: '🥜'),
      SubCategory(label: 'Snacks', emoji: '🍿'),
      SubCategory(label: 'Other', emoji: '🥡'),
    ],
    sizes: const [
      ParcelSize(label: 'Small', weightKg: 1.0, price: 60),
      ParcelSize(label: 'Medium', weightKg: 2.0, price: 100),
      ParcelSize(label: 'Large', weightKg: 3.0, price: 150),
    ],
  ),
  MainCategory(
    label: 'Electronics',
    emoji: '📱',
    color: secondaryColor,
    icon: Icons.devices_outlined,
      pricePerKm: 8, // ₹8/km
    subCategories: const [
      SubCategory(label: 'Mobile / Tablet', emoji: '📱'),
      SubCategory(label: 'Laptop', emoji: '💻'),
      SubCategory(label: 'Charger / Cable', emoji: '🔌'),
      SubCategory(label: 'Earphones', emoji: '🎧'),
      SubCategory(label: 'Smartwatch', emoji: '⌚'),
      SubCategory(label: 'Other', emoji: '🖥️'),
    ],
    sizes: const [
      ParcelSize(label: 'Small', weightKg: 1.0, price: 100),
      ParcelSize(label: 'Medium', weightKg: 2.0, price: 160),
      ParcelSize(label: 'Large', weightKg: 3.0, price: 230),
    ],
  ),
  MainCategory(
    label: 'Clothing',
    emoji: '👕',
    color: Color(0xFF10B981),
    icon: Icons.checkroom_outlined,
      pricePerKm: 2, // ₹2/km
    subCategories: const [
      SubCategory(label: 'Casual Wear', emoji: '👕'),
      SubCategory(label: 'Ethnic / Saree', emoji: '🥻'),
      SubCategory(label: 'Kids Clothing', emoji: '🧒'),
      SubCategory(label: 'Shoes / Footwear', emoji: '👟'),
      SubCategory(label: 'Accessories', emoji: '👜'),
      SubCategory(label: 'Other', emoji: '🧣'),
    ],
    sizes: const [
      ParcelSize(label: 'Small', weightKg: 1.0, price: 55),
      ParcelSize(label: 'Medium', weightKg: 2.0, price: 90),
      ParcelSize(label: 'Large', weightKg: 3.0, price: 130),
    ],
  ),
  MainCategory(
    label: 'Other',
    emoji: '📦',
    color: Color(0xFF8B5CF6),
    icon: Icons.category_outlined,
      pricePerKm: 5, // ₹5/km
    subCategories: const [
      SubCategory(label: 'Gift', emoji: '🎁'),
      SubCategory(label: 'Medicines', emoji: '💊'),
      SubCategory(label: 'Books', emoji: '📖'),
      SubCategory(label: 'Toys', emoji: '🧸'),
      SubCategory(label: 'Hardware / Tools', emoji: '🔧'),
      SubCategory(label: 'Other', emoji: '📦'),
    ],
    sizes: const [
      ParcelSize(label: 'Small', weightKg: 1.0, price: 50),
      ParcelSize(label: 'Medium', weightKg: 2.0, price: 85),
      ParcelSize(label: 'Large', weightKg: 3.0, price: 120),
    ],
  ),
];

// City areas mapping
const cityAreas = {
  'Nashik': [
    'Gangapur Road',
    'College Road',
    'Panchavati',
    'Indira Nagar',
    'Cidco',
  ],
  'Pune': ['Kothrud', 'Baner', 'Wakad', 'Hinjewadi', 'Shivaji Nagar'],
  'Mumbai': ['Andheri', 'Borivali', 'Dadar', 'Thane', 'Bandra'],
  'Aurangabad': ['Jalna Road', 'CIDCO', 'Osmanpura', 'Garkheda'],
  'Nagpur': ['Dharampeth', 'Sitabuldi', 'Mahal', 'Civil Lines'],
};

// ---------- Address Autocomplete Field (using flutter_typeahead) ----------
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

// ---------- Main Screen ----------
class CreateParcelScreen extends StatefulWidget {
  const CreateParcelScreen({super.key});

  @override
  State<CreateParcelScreen> createState() => _CreateParcelScreenState();
}

class _CreateParcelScreenState extends State<CreateParcelScreen>
    with SingleTickerProviderStateMixin {
  static const _cloudName = 'dwjzuw8fd';
  static const _uploadPreset = 'parcel_upload';
double _calculateTotalPrice() {
  if (_distanceKm == null ||
      _selectedCategory == null ||
      _selectedSize == null) {
    return 0;
  }

  double basePrice = _selectedSize!.price;
  double distanceCharge =
      _distanceKm! * _selectedCategory!.pricePerKm;

  return basePrice + distanceCharge;
}
  // Form keys & controllers
  final _formKey = GlobalKey<FormState>();
  final _receiverCtrl = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _descCtrl = TextEditingController();
  final _otherSubCtrl = TextEditingController();
  final _pickupAddressCtrl = TextEditingController();
  final _dropAddressCtrl = TextEditingController();

  // Sender info
  String? _senderName;
  String? _senderEmail;

  // Locations
  Location _pickup = Location();
  Location _drop = Location();
  final _cities = ['Nashik', 'Pune', 'Mumbai', 'Aurangabad', 'Nagpur'];

  // Deadline
  DateTime? _deadlineDate;
  TimeOfDay? _deadlineTime;
  DateTime? get _deadline {
    if (_deadlineDate == null || _deadlineTime == null) return null;
    return DateTime(
      _deadlineDate!.year,
      _deadlineDate!.month,
      _deadlineDate!.day,
      _deadlineTime!.hour,
      _deadlineTime!.minute,
    );
  }

  // Category selection
  MainCategory? _selectedCategory;
  SubCategory? _selectedSub;
  ParcelSize? _selectedSize;

  // Photo
  File? _imageFile;
  bool _isUploading = false;
  bool _isLoading = false;

  // Route preview
  double? _distanceKm;
  int? _etaMinutes;

  // Animations
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();
    _fetchSenderInfo();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _receiverCtrl.dispose();
    _receiverPhone.dispose();
    _descCtrl.dispose();
    _otherSubCtrl.dispose();
    _pickupAddressCtrl.dispose();
    _dropAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchSenderInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    setState(() {
      _senderName = doc.data()?['name'] as String? ?? 'Unknown';
      _senderEmail = doc.data()?['email'] as String? ?? '';
    });
  }

  // ---------- Location Helpers ----------
  List<String> _getAreasForCity(String city) => cityAreas[city] ?? [];

double _calculateDistance(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadius = 6371;

  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);

  final a =
      (math.sin(dLat / 2) * math.sin(dLat / 2)) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          (math.sin(dLon / 2) * math.sin(dLon / 2));

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadius * c;
}

double _degToRad(double deg) {
  return deg * (math.pi / 180);
}

  void _updatePickupLocation(String address, double? lat, double? lng) {
    setState(() {
      _pickup.address = address;
      _pickup.latitude = lat;
      _pickup.longitude = lng;
    });
    _calculateRoute();
  }

  void _updateDropLocation(String address, double? lat, double? lng) {
    setState(() {
      _drop.address = address;
      _drop.latitude = lat;
      _drop.longitude = lng;
    });
    _calculateRoute();
  }

//   void _calculateRoute() {
//   if (_pickup.latitude != null &&
//       _pickup.longitude != null &&
//       _drop.latitude != null &&
//       _drop.longitude != null) {

//     final distance = _calculateDistance(
//       _pickup.latitude!,
//       _pickup.longitude!,
//       _drop.latitude!,
//       _drop.longitude!,
//     );

//     // Assume average travel speed 40 km/h for preview
//     final eta = ((distance / 40) * 60).ceil();

//     setState(() {
//       _distanceKm = distance;
//       _etaMinutes = eta;
//     });
//   } else {
//     setState(() {
//       _distanceKm = null;
//       _etaMinutes = null;
//     });
//   }
// }
Future<void> _calculateRoute() async {
  if (_pickup.latitude != null &&
      _pickup.longitude != null &&
      _drop.latitude != null &&
      _drop.longitude != null) {

    try {
      final url = Uri.parse(
        "https://router.project-osrm.org/route/v1/driving/"
        "${_pickup.longitude},${_pickup.latitude};"
        "${_drop.longitude},${_drop.latitude}"
        "?overview=false",
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final route = data["routes"][0];

        final distanceMeters = route["distance"];
        final durationSeconds = route["duration"];

        final distanceKm = distanceMeters / 1000;
        final etaMinutes = (durationSeconds / 60).ceil();

        setState(() {
          _distanceKm = distanceKm;
          _etaMinutes = etaMinutes;
        });
      }
    } catch (e) {
      debugPrint("Route error: $e");
    }
  } else {
    setState(() {
      _distanceKm = null;
      _etaMinutes = null;
    });
  }
}
  // ---------- Image picker ----------
  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1024,
    );
    if (picked != null) setState(() => _imageFile = File(picked.path));
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Upload Parcel Photo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ImageOption(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ImageOption(
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

  // ---------- Deadline pickers ----------
  Future<void> _selectDeadlineDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _deadlineDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(
          context,
        ).copyWith(colorScheme: const ColorScheme.light(primary: primaryColor)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _deadlineDate = picked);
  }

  Future<void> _selectDeadlineTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _deadlineTime ?? TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: Theme.of(
          context,
        ).copyWith(colorScheme: const ColorScheme.light(primary: primaryColor)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _deadlineTime = picked);
  }

  // ---------- Cloudinary upload ----------
  Future<String> _uploadPhoto(File imageFile) async {
    setState(() => _isUploading = true);
    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
      );
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder'] = 'parcels'
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['secure_url'] as String;
      } else {
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      _showSnack('Photo upload failed: $e', isError: true);
      return '';
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ---------- Form submission ----------
  Future<void> _submitParcel() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      return _showSnack('Please select a category', isError: true);
    }
    if (_selectedSub == null) {
      return _showSnack('Please select a sub-category', isError: true);
    }
    if (_selectedSize == null) {
      return _showSnack('Please select a parcel size', isError: true);
    }
    if (_pickup.city.isEmpty ||
        _pickup.area.isEmpty ||
        _pickup.address.isEmpty) {
      return _showSnack('Please complete pickup location', isError: true);
    }
    if (_drop.city.isEmpty || _drop.area.isEmpty || _drop.address.isEmpty) {
      return _showSnack('Please complete drop location', isError: true);
    }
    if (_pickup.address == _drop.address ) {
      return _showSnack(
        'Pickup and drop cannot be the same address',
        isError: true,
      );
    }
    if (_deadline == null) {
      return _showSnack('Please select delivery deadline', isError: true);
    }
    if (_deadline!.isBefore(DateTime.now())) {
      return _showSnack('Deadline must be in the future', isError: true);
    }

    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      String photoUrl = '';
      if (_imageFile != null) photoUrl = await _uploadPhoto(_imageFile!);

      final subLabel =
          _selectedSub!.label == 'Other' && _otherSubCtrl.text.trim().isNotEmpty
          ? _otherSubCtrl.text.trim()
          : _selectedSub!.label;

      // Build the parcel data, keeping original fields for compatibility
      final parcelData = {
        // Sender info
        'senderId': uid,
        'senderName': _senderName ?? '',
        'senderEmail': _senderEmail ?? '',

        // Original location fields (kept for backward compatibility)
        'fromCity': _pickup.city,
        'toCity': _drop.city,

        // New detailed location objects
        'pickup': _pickup.toJson(),
        'drop': _drop.toJson(),
        'distanceKm': _distanceKm,
        'etaMinutes': _etaMinutes,

        // Category and size
        'category': _selectedCategory!.label,
        'subCategory': subLabel,
        'size': _selectedSize!.label,
        'weight': _selectedSize!.weightKg,

        // Parcel details
        'description': _descCtrl.text.trim(),
        'receiverName': _receiverCtrl.text.trim(),
        'receiverPhone': _receiverPhone.text.trim(),
        'photoUrl': photoUrl,
        'price': _calculateTotalPrice(),

        // Status and timestamps
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'deliveryDeadline': Timestamp.fromDate(_deadline!),

        // Fields that may be populated later
        'ignoredTravelers': [], // initialize empty array
        'travelerId': null,
        'travelerName': null,
        'requestedAt': null, // will be set when a traveler is requested
      };

      final docRef = await FirebaseFirestore.instance
          .collection('parcels')
          .add(parcelData);

      _showSnack('✅ Parcel posted successfully!', isError: false);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) context.push('/available-traveler/${docRef.id}');
    } catch (e) {
      _showSnack('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            size: 20,
            color: textPrimary,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go("/sender");
            }
          },
        ),
        title: const Text(
          'Send a Parcel',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        actions: [
          if (_selectedSize != null)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: secondaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.currency_rupee,
                    size: 14,
                    color: secondaryColor,
                  ),
                  Text(
                    _selectedSize!.price.toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: secondaryColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Sender Information
                _SectionCard(
                  title: 'Sender Information',
                  icon: Icons.person_outline,
                  color: primaryColor,
                  child: _SenderInfoTile(
                    name: _senderName ?? 'Loading...',
                    email: _senderEmail ?? '',
                  ),
                ),
                const SizedBox(height: 16),

                // Pickup Location
                _SectionCard(
                  title: 'Pickup Location',
                  icon: Icons.location_on_outlined,
                  color: primaryColor,
                  child: _LocationPicker(
                    location: _pickup,
                    cities: _cities,
                    areas: _getAreasForCity(_pickup.city),
                    onCityChanged: (city) => setState(() {
                      _pickup.city = city;
                      _pickup.area = '';
                      _pickup.address = '';
                      _pickup.latitude = null;
                      _pickup.longitude = null;
                      _pickupAddressCtrl.clear();
                      _calculateRoute();
                    }),
                    onAreaChanged: (area) =>
                        setState(() => _pickup.area = area ?? ''),
                    addressController: _pickupAddressCtrl,
                    onAddressSelected: _updatePickupLocation,
                    hint: 'Search pickup address',
                  ),
                ),
                const SizedBox(height: 16),

                // Drop Location
                _SectionCard(
                  title: 'Drop Location',
                  icon: Icons.location_on_outlined,
                  color: primaryColor,
                  child: _LocationPicker(
                    location: _drop,
                    cities: _cities,
                    areas: _getAreasForCity(_drop.city),
                    onCityChanged: (city) => setState(() {
                      _drop.city = city;
                      _drop.area = '';
                      _drop.address = '';
                      _drop.latitude = null;
                      _drop.longitude = null;
                      _dropAddressCtrl.clear();
                      _calculateRoute();
                    }),
                    onAreaChanged: (area) =>
                        setState(() => _drop.area = area ?? ''),
                    addressController: _dropAddressCtrl,
                    onAddressSelected: _updateDropLocation,
                    hint: 'Search drop address',
                  ),
                ),

                // Route Preview (if both locations have coordinates)
                if (_pickup.latitude != null && _drop.latitude != null) ...[
                  const SizedBox(height: 12),
                  _RoutePreviewCard(distance: _distanceKm, eta: _etaMinutes),
                ],
                const SizedBox(height: 16),

                // Delivery Deadline
                _SectionCard(
                  title: 'Delivery Deadline',
                  icon: Icons.event_available_outlined,
                  color: primaryColor,
                  child: Column(
                    children: [
                      _DeadlinePicker(
                        label: 'Date',
                        value: _deadlineDate != null
                            ? DateFormat('dd MMM yyyy').format(_deadlineDate!)
                            : null,
                        icon: Icons.calendar_today_rounded,
                        onTap: _selectDeadlineDate,
                      ),
                      const SizedBox(height: 12),
                      _DeadlinePicker(
                        label: 'Time',
                        value: _deadlineTime != null
                            ? _deadlineTime!.format(context)
                            : null,
                        icon: Icons.access_time_rounded,
                        onTap: _selectDeadlineTime,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Category accordion
                const Padding(
                  padding: EdgeInsets.only(left: 2, bottom: 12),
                  child: Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ),
                ...mainCategories.map(_buildCategoryCard),
                const SizedBox(height: 16),

                // Parcel Details
                _SectionCard(
                  title: 'Parcel Details',
                  icon: Icons.inventory_2_outlined,
                  color: primaryColor,
                  child: TextFormField(
                    controller: _descCtrl,
                    maxLines: 2,
                    decoration: _inputDeco(
                      'What are you sending?',
                      Icons.description_outlined,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Description required' : null,
                  ),
                ),
                const SizedBox(height: 16),

                // Receiver Information
                _SectionCard(
                  title: 'Receiver Information',
                  icon: Icons.person_pin_outlined,
                  color: primaryColor,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _receiverCtrl,
                        decoration: _inputDeco(
                          'Receiver full name',
                          Icons.person_outline,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Receiver name required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _receiverPhone,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: _inputDeco(
                          'Receiver mobile number',
                          Icons.phone_outlined,
                          prefix: '+91 ',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Mobile required';
                          if (v.trim().length != 10)
                            return 'Enter valid 10-digit number';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Parcel Photo
                _SectionCard(
                  title: 'Parcel Photo',
                  icon: Icons.camera_alt_outlined,
                  color: primaryColor,
                  child: _imageFile == null
                      ? GestureDetector(
                          onTap: _showImagePicker,
                          child: Container(
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_a_photo_outlined,
                                  color: primaryColor,
                                  size: 32,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to upload photo',
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _imageFile!,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            if (_isUploading)
                              Container(
                                height: 160,
                                color: Colors.black54,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: _showImagePicker,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.edit,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Change',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),

                // Price Summary
                if (_selectedSize != null) ...[
                  _buildPriceSummary(),
                  const SizedBox(height: 16),
                ],

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitParcel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Posting...'),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.send_rounded, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Post Parcel',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Category Accordion ----------
  Widget _buildCategoryCard(MainCategory cat) {
    final isSelected = _selectedCategory?.label == cat.label;
    return GestureDetector(
      onTap: () => setState(() {
        if (isSelected) {
          _selectedCategory = null;
          _selectedSub = null;
          _selectedSize = null;
        } else {
          _selectedCategory = cat;
          _selectedSub = null;
          _selectedSize = null;
          _otherSubCtrl.clear();
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? cat.color : cardBorder,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: cat.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        cat.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? cat.color : textPrimary,
                          ),
                        ),
                        Text(
                          '${cat.subCategories.length} types',
                          style: const TextStyle(
                            fontSize: 11,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected && _selectedSub != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cat.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_selectedSub!.emoji} ${_selectedSub!.label}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cat.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  AnimatedRotation(
                    turns: isSelected ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: isSelected ? cat.color : textSecondary,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            if (isSelected) ...[
              Divider(
                color: cat.color.withOpacity(0.2),
                height: 1,
                indent: 14,
                endIndent: 14,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Sub-category',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cat.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Sub-category dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: cat.color.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cat.color.withOpacity(0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          hint: Text(
                            'Choose ${cat.label.toLowerCase()} type',
                            style: const TextStyle(
                              fontSize: 13,
                              color: textSecondary,
                            ),
                          ),
                          value: _selectedSub?.label,
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: cat.color,
                            size: 20,
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cat.color,
                          ),
                          dropdownColor: Colors.white,
                          items: cat.subCategories.map((sub) {
                            return DropdownMenuItem(
                              value: sub.label,
                              child: Row(
                                children: [
                                  Text(
                                    sub.emoji,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    sub.label,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() {
                            _selectedSub = cat.subCategories.firstWhere(
                              (s) => s.label == val,
                            );
                            _selectedSize = null;
                            _otherSubCtrl.clear();
                          }),
                        ),
                      ),
                    ),
                    if (_selectedSub?.label == 'Other') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otherSubCtrl,
                        decoration: _inputDeco(
                          'Describe your item',
                          Icons.edit_outlined,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Please describe your item'
                            : null,
                      ),
                    ],
                    // Sizes
                    if (_selectedSub != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Select Parcel Size',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cat.color,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...cat.sizes.map((size) {
                        final isSel = _selectedSize?.label == size.label;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedSize = size),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? cat.color.withOpacity(0.07)
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? cat.color : cardBorder,
                                width: isSel ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? cat.color.withOpacity(0.15)
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      size.label == 'A4 Envelope'
                                          ? '✉️'
                                          : size.label == 'File Folder'
                                          ? '📁'
                                          : '📦',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        size.label,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: isSel
                                              ? cat.color
                                              : textPrimary,
                                        ),
                                      ),
                                      Text(
                                        'Up to ${size.weightKg} kg',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? cat.color
                                        : cat.color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '₹${size.price.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isSel ? Colors.white : cat.color,
                                    ),
                                  ),
                                ),
                                if (isSel) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: cat.color,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSummary() {
    
    final cat = _selectedCategory!;
    final sub = _selectedSub!;
    final size = _selectedSize!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'Price Summary',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PriceRow(label: 'Category', value: '${cat.emoji}  ${cat.label}'),
          _PriceRow(label: 'Sub-category', value: '${sub.emoji}  ${sub.label}'),
          _PriceRow(label: 'Size', value: size.label),
          _PriceRow(label: 'Weight', value: '${size.weightKg} kg'),
          _PriceRow(
  label: 'Distance',
  value: '${_distanceKm?.toStringAsFixed(1) ?? 0} km',
),

_PriceRow(
  label: 'Per KM Charge',
  value: '₹${_selectedCategory!.pricePerKm}/km',
),

_PriceRow(
  label: 'Distance Cost',
  value:
      '₹${((_distanceKm ?? 0) * _selectedCategory!.pricePerKm).toStringAsFixed(0)}',
),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: Colors.white24, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Price',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: secondaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '₹${_calculateTotalPrice().toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '* Price based on category, sub-category & size',
            style: TextStyle(fontSize: 10, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon, {String? prefix}) =>
      InputDecoration(
        hintText: hint,
        prefixText: prefix,
        prefixStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        prefixIcon: Icon(icon, size: 20, color: textSecondary),
        counterText: '',
        filled: true,
        fillColor: Colors.grey[50],
        hintStyle: const TextStyle(fontSize: 13, color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      );
}

// ---------- Reusable Widgets ----------
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: cardBorder, height: 1),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SenderInfoTile extends StatelessWidget {
  final String name, email;
  const _SenderInfoTile({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: primaryColor.withOpacity(0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'S',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryColor,
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
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              Text(
                email,
                style: const TextStyle(fontSize: 12, color: textSecondary),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: secondaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Verified',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: secondaryColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationPicker extends StatelessWidget {
  final Location location;
  final List<String> cities;
  final List<String> areas;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String?> onAreaChanged;
  final TextEditingController addressController;
  final Function(String address, double? lat, double? lng) onAddressSelected;
  final String hint;

  const _LocationPicker({
    required this.location,
    required this.cities,
    required this.areas,
    required this.onCityChanged,
    required this.onAreaChanged,
    required this.addressController,
    required this.onAddressSelected,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // City dropdown
        DropdownButtonFormField<String>(
          value: location.city.isEmpty ? null : location.city,
          decoration: _inputDeco('Select city', Icons.location_city),
          items: cities
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (val) => onCityChanged(val!),
          validator: (_) => location.city.isEmpty ? 'City required' : null,
        ),
        const SizedBox(height: 12),
        // Area dropdown (depends on city)
        DropdownButtonFormField<String>(
          value: location.area.isEmpty ? null : location.area,
          decoration: _inputDeco('Select area', Icons.map),
          items: areas
              .map((a) => DropdownMenuItem(value: a, child: Text(a)))
              .toList(),
          onChanged: onAreaChanged,
          validator: (_) => location.area.isEmpty ? 'Area required' : null,
        ),
        const SizedBox(height: 12),
        // Address autocomplete (using flutter_typeahead)
        AddressAutocompleteField(
          controller: addressController,
          city: location.city,
          area: location.area, // ✅ PASS CITY
          hintText: hint,
          prefixIcon: Icons.search,
          onSelected: onAddressSelected,
        ),
        if (location.latitude != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle, color: secondaryColor, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Coordinates set',
                  style: TextStyle(color: secondaryColor, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, size: 20, color: textSecondary),
    filled: true,
    fillColor: Colors.grey[50],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: primaryColor, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

class _DeadlinePicker extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;
  const _DeadlinePicker({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value != null ? primaryColor : cardBorder,
            width: value != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: value != null ? primaryColor : textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? 'Select $label',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: value != null
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: value != null ? textPrimary : textSecondary,
                ),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.edit, size: 14, color: primaryColor),
                ),
              )
            else
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

class _RoutePreviewCard extends StatelessWidget {
  final double? distance;
  final int? eta;
  const _RoutePreviewCard({this.distance, this.eta});
 String _formatEta(int minutes) {
    if (minutes < 60) {
      return "$minutes min";
    }

    final hours = minutes ~/ 60;
    final mins = minutes % 60;

    if (mins == 0) {
      return "$hours hr";
    }

    return "$hours hr $mins min";
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.route, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Route Preview',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Distance: ${distance?.toStringAsFixed(1) ?? '--'} Km  ETA: ${eta != null ? _formatEta(eta!) : '--'}',
                  style: const TextStyle(fontSize: 13, color: textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ImageOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: primaryColor),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label, value;
  const _PriceRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
