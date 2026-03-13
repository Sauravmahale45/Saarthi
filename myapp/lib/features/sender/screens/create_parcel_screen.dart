import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart'; // for date formatting

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _ParcelSize {
  final String label;
  final double weightKg;
  final double price;
  const _ParcelSize({
    required this.label,
    required this.weightKg,
    required this.price,
  });
}

class _SubCategory {
  final String label;
  final String emoji;
  const _SubCategory({required this.label, required this.emoji});
}

class _MainCategory {
  final String label;
  final String emoji;
  final Color color;
  final IconData icon;
  final List<_SubCategory> subCategories;
  final List<_ParcelSize> sizes;
  const _MainCategory({
    required this.label,
    required this.emoji,
    required this.color,
    required this.icon,
    required this.subCategories,
    required this.sizes,
  });
}

// ─── All categories with subcategories and size/price tiers ──────────────────
final _mainCategories = [
  _MainCategory(
    label: 'Document',
    emoji: '📄',
    color: Color(0xFF6366F1),
    icon: Icons.description_outlined,
    subCategories: [
      _SubCategory(label: 'Legal Papers', emoji: '⚖️'),
      _SubCategory(label: 'Certificate', emoji: '🏅'),
      _SubCategory(label: 'ID / Passport', emoji: '🪪'),
      _SubCategory(label: 'Invoice / Bill', emoji: '🧾'),
      _SubCategory(label: 'Academic Papers', emoji: '📚'),
      _SubCategory(label: 'Other', emoji: '📋'),
    ],
    sizes: [
      _ParcelSize(label: 'Small', weightKg: 0.5, price: 40),
      _ParcelSize(label: 'Medium', weightKg: 1.0, price: 70),
      _ParcelSize(label: 'Large', weightKg: 2.0, price: 110),
    ],
  ),
  _MainCategory(
    label: 'Food',
    emoji: '🍱',
    color: Color(0xFFFF6B35),
    icon: Icons.fastfood_outlined,
    subCategories: [
      _SubCategory(label: 'Seasonal Items', emoji: '🌾'),
      _SubCategory(label: 'Home-cooked Meal', emoji: '🍲'),
      _SubCategory(label: 'Sweets / Mithai', emoji: '🍬'),
      _SubCategory(label: 'Dry Fruits / Nuts', emoji: '🥜'),
      _SubCategory(label: 'Snacks', emoji: '🍿'),
      _SubCategory(label: 'Other', emoji: '🥡'),
    ],
    sizes: [
      _ParcelSize(label: 'Small', weightKg: 1.0, price: 60),
      _ParcelSize(label: 'Medium', weightKg: 2.0, price: 100),
      _ParcelSize(label: 'Large', weightKg: 3.0, price: 150),
    ],
  ),
  _MainCategory(
    label: 'Electronics',
    emoji: '📱',
    color: Color(0xFF3B82F6),
    icon: Icons.devices_outlined,
    subCategories: [
      _SubCategory(label: 'Mobile / Tablet', emoji: '📱'),
      _SubCategory(label: 'Laptop', emoji: '💻'),
      _SubCategory(label: 'Charger / Cable', emoji: '🔌'),
      _SubCategory(label: 'Earphones', emoji: '🎧'),
      _SubCategory(label: 'Smartwatch', emoji: '⌚'),
      _SubCategory(label: 'Other', emoji: '🖥️'),
    ],
    sizes: [
      _ParcelSize(label: 'Small', weightKg: 1.0, price: 100),
      _ParcelSize(label: 'Medium', weightKg: 2.0, price: 160),
      _ParcelSize(label: 'Large', weightKg: 3.0, price: 230),
    ],
  ),
  _MainCategory(
    label: 'Clothing',
    emoji: '👕',
    color: Color(0xFF10B981),
    icon: Icons.checkroom_outlined,
    subCategories: [
      _SubCategory(label: 'Casual Wear', emoji: '👕'),
      _SubCategory(label: 'Ethnic / Saree', emoji: '🥻'),
      _SubCategory(label: 'Kids Clothing', emoji: '🧒'),
      _SubCategory(label: 'Shoes / Footwear', emoji: '👟'),
      _SubCategory(label: 'Accessories', emoji: '👜'),
      _SubCategory(label: 'Other', emoji: '🧣'),
    ],
    sizes: [
      _ParcelSize(label: 'Small', weightKg: 1.0, price: 55),
      _ParcelSize(label: 'Medium', weightKg: 2.0, price: 90),
      _ParcelSize(label: 'Large', weightKg: 3.0, price: 130),
    ],
  ),
  _MainCategory(
    label: 'Other',
    emoji: '📦',
    color: Color(0xFF8B5CF6),
    icon: Icons.category_outlined,
    subCategories: [
      _SubCategory(label: 'Gift', emoji: '🎁'),
      _SubCategory(label: 'Medicines', emoji: '💊'),
      _SubCategory(label: 'Books', emoji: '📖'),
      _SubCategory(label: 'Toys', emoji: '🧸'),
      _SubCategory(label: 'Hardware / Tools', emoji: '🔧'),
      _SubCategory(label: 'Other', emoji: '📦'),
    ],
    sizes: [
      _ParcelSize(label: 'Small', weightKg: 1.0, price: 50),
      _ParcelSize(label: 'Medium', weightKg: 2.0, price: 85),
      _ParcelSize(label: 'Large', weightKg: 3.0, price: 120),
    ],
  ),
];

// ═══════════════════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class CreateParcelScreen extends StatefulWidget {
  const CreateParcelScreen({super.key});

  @override
  State<CreateParcelScreen> createState() => _CreateParcelScreenState();
}

class _CreateParcelScreenState extends State<CreateParcelScreen>
    with SingleTickerProviderStateMixin {
  static const _cloudName = 'dwjzuw8fd';
  static const _uploadPreset = 'parcel_upload';

  // ── Form ──────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _receiverCtrl = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _descCtrl = TextEditingController();
  final _otherSubCtrl = TextEditingController();

  // ── State ─────────────────────────────────────────────────────────────────
  String _fromCity = 'Nashik';
  String _toCity = 'Pune';
  bool _isLoading = false;
  bool _isUploading = false;
  File? _imageFile;
  String? _senderName;
  String? _senderEmail;
  DateTime? _deliveryDeadline; // NEW: deadline

  _MainCategory? _selectedCategory;
  _SubCategory? _selectedSub;
  _ParcelSize? _selectedSize;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  final _cities = ['Nashik', 'Pune', 'Mumbai', 'Aurangabad', 'Nagpur'];

  double get _autoPrice => _selectedSize?.price ?? 0;

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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // NEW: method to select deadline date
  Future<void> _selectDeadline() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _deliveryDeadline ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF6B35),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1A1A1A),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B35),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _deliveryDeadline = picked;
      });
    }
  }

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

  Future<void> _submitParcel() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      _showSnack('Please select a category', isError: true);
      return;
    }
    if (_selectedSub == null) {
      _showSnack('Please select a sub-category', isError: true);
      return;
    }
    if (_selectedSize == null) {
      _showSnack('Please select a parcel size', isError: true);
      return;
    }
    if (_fromCity == _toCity) {
      _showSnack('From and To city cannot be the same', isError: true);
      return;
    }
    // NEW: validate deadline
    if (_deliveryDeadline == null) {
      _showSnack('Please select a delivery deadline', isError: true);
      return;
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

      // FIX: Perform only one add and capture the reference
      DocumentReference
      parcelRef = await FirebaseFirestore.instance.collection('parcels').add({
        'senderId': uid,
        'senderName': _senderName ?? '',
        'senderEmail': _senderEmail ?? '',
        'fromCity': _fromCity,
        'toCity': _toCity,
        'category': _selectedCategory!.label,
        'subCategory': subLabel,
        'size': _selectedSize!.label,
        'weight': _selectedSize!.weightKg,
        'description': _descCtrl.text.trim(),
        'receiverName': _receiverCtrl.text.trim(),
        'receiverPhone': _receiverPhone.text.trim(),
        'photoUrl': photoUrl,
        'price': _autoPrice,
        'status': 'pending',
        'travelerId': null,
        'travelerName': null,
        'createdAt': FieldValue.serverTimestamp(),
        'deliveryDeadline': Timestamp.fromDate(_deliveryDeadline!), // NEW field
      });

      if (mounted) {
        _showSnack('✅ Parcel posted successfully!', isError: false);
        await Future.delayed(const Duration(milliseconds: 800));
        // Navigate to available travelers screen with the new parcel ID
        context.push('/available-traveler/${parcelRef.id}');
      }
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
        backgroundColor: isError
            ? const Color(0xFFEF4444)
            : const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
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
            size: 20,
            color: Color(0xFF1A1A1A),
          ),
          onPressed: () => context.go('/sender'),
        ),
        title: const Text(
          'Send a Parcel',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
        actions: [
          if (_autoPrice > 0)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.currency_rupee,
                    size: 14,
                    color: Color(0xFF22C55E),
                  ),
                  Text(
                    _autoPrice.toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF22C55E),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Sender Info ──────────────────────────────────────────────
                _SectionCard(
                  title: 'Sender Information',
                  icon: Icons.person_outline,
                  color: const Color(0xFFFF6B35),
                  child: _SenderInfoTile(
                    name: _senderName ?? 'Loading...',
                    email: _senderEmail ?? '',
                  ),
                ),
                const SizedBox(height: 16),

                // ── Route ────────────────────────────────────────────────────
                _SectionCard(
                  title: 'Route',
                  icon: Icons.route_outlined,
                  color: const Color(0xFFFF6B35),
                  child: Row(
                    children: [
                      Expanded(
                        child: _CityDropdown(
                          label: 'From',
                          value: _fromCity,
                          items: _cities,
                          onChanged: (v) => setState(() => _fromCity = v!),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B35).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                      Expanded(
                        child: _CityDropdown(
                          label: 'To',
                          value: _toCity,
                          items: _cities,
                          onChanged: (v) => setState(() => _toCity = v!),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── NEW: Delivery Deadline ───────────────────────────────────
                _SectionCard(
                  title: 'Delivery Deadline',
                  icon: Icons.event_available_outlined,
                  color: const Color(0xFFFF6B35),
                  child: GestureDetector(
                    onTap: _selectDeadline,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _deliveryDeadline != null
                              ? const Color(0xFFFF6B35)
                              : const Color(0xFFEEEEEE),
                          width: _deliveryDeadline != null ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 20,
                            color: _deliveryDeadline != null
                                ? const Color(0xFFFF6B35)
                                : const Color(0xFF888888),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _deliveryDeadline != null
                                  ? DateFormat(
                                      'dd MMM yyyy',
                                    ).format(_deliveryDeadline!)
                                  : 'Select deadline date',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: _deliveryDeadline != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: _deliveryDeadline != null
                                    ? const Color(0xFF1A1A1A)
                                    : const Color(0xFFAAAAAA),
                              ),
                            ),
                          ),
                          if (_deliveryDeadline != null)
                            GestureDetector(
                              onTap: () {
                                setState(() => _deliveryDeadline = null);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFF6B35,
                                  ).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Color(0xFFFF6B35),
                                ),
                              ),
                            )
                          else
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                              color: Color(0xFFCCCCCC),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Category accordion ───────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.only(left: 2, bottom: 12),
                  child: Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                ..._mainCategories.map(_buildCategoryCard),
                const SizedBox(height: 16),

                // ── Description ──────────────────────────────────────────────
                _SectionCard(
                  title: 'Parcel Details',
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFFFF6B35),
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

                // ── Receiver ─────────────────────────────────────────────────
                _SectionCard(
                  title: 'Receiver Information',
                  icon: Icons.person_pin_outlined,
                  color: const Color(0xFFFF6B35),
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
                      const SizedBox(height: 14),
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

                // ── Photo ─────────────────────────────────────────────────────
                _SectionCard(
                  title: 'Parcel Photo',
                  icon: Icons.camera_alt_outlined,
                  color: const Color(0xFFFF6B35),
                  child: _imageFile == null
                      ? GestureDetector(
                          onTap: _showImagePicker,
                          child: Container(
                            width: double.infinity,
                            height: 120,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F8F8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFDDDDDD),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFF6B35,
                                    ).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_a_photo_outlined,
                                    color: Color(0xFFFF6B35),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Tap to upload photo',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF6B35),
                                  ),
                                ),
                                const Text(
                                  'Camera or Gallery',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF888888),
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
                                width: double.infinity,
                                height: 160,
                                fit: BoxFit.cover,
                              ),
                            ),
                            if (_isUploading)
                              Container(
                                width: double.infinity,
                                height: 160,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Uploading...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
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
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
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
                        ),
                ),
                const SizedBox(height: 20),

                // ── Price summary ─────────────────────────────────────────────
                if (_selectedSize != null) ...[
                  _buildPriceSummary(),
                  const SizedBox(height: 20),
                ],

                // ── Submit ────────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitParcel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
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
                              Text(
                                'Posting Parcel...',
                                style: TextStyle(fontSize: 16),
                              ),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORY ACCORDION CARD
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildCategoryCard(_MainCategory cat) {
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
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? cat.color : const Color(0xFFEEEEEE),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? cat.color.withOpacity(0.12)
                  : Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
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
                            color: isSelected
                                ? cat.color
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          '${cat.subCategories.length} types available',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Badge showing selected sub
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
                      color: isSelected ? cat.color : const Color(0xFF888888),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            // ── Expanded body ────────────────────────────────────────────────
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
                    // Sub-category label
                    Text(
                      'Select Sub-category',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cat.color,
                        letterSpacing: 0.3,
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
                              color: Color(0xFFAAAAAA),
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
                            return DropdownMenuItem<String>(
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
                                      color: Color(0xFF1A1A1A),
                                      fontWeight: FontWeight.w500,
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

                    // "Other" free-text input
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

                    // ── Parcel sizes (shown after sub is chosen) ─────────────
                    if (_selectedSub != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Select Parcel Size',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cat.color,
                          letterSpacing: 0.3,
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
                                  : const Color(0xFFF8F8F8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel
                                    ? cat.color
                                    : const Color(0xFFEEEEEE),
                                width: isSel ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Icon
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? cat.color.withOpacity(0.15)
                                        : const Color(0xFFEEEEEE),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      size.label == 'Small'
                                          ? '📦'
                                          : size.label == 'Medium'
                                          ? '🗃️'
                                          : '📫',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Label + weight
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
                                              : const Color(0xFF1A1A1A),
                                        ),
                                      ),
                                      Text(
                                        size.label == 'Small'
                                            ? 'Up to ${size.weightKg} kg'
                                            : size.label == 'Medium'
                                            ? 'Up to ${size.weightKg} kg'
                                            : 'Up to ${size.weightKg} kg',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF888888),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Price chip
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

  // ── Price Summary ──────────────────────────────────────────────────────────
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                color: Colors.white70,
                size: 16,
              ),
              SizedBox(width: 6),
              Text(
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
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '₹${size.price.toStringAsFixed(0)}',
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
          color: Color(0xFF1A1A1A),
        ),
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF888888)),
        counterText: '',
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEEEEEE), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

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
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFF0F0F0), height: 1),
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
          backgroundColor: const Color(0xFFFF6B35).withOpacity(0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'S',
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
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              Text(
                email,
                style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Verified',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF22C55E),
            ),
          ),
        ),
      ],
    );
  }
}

class _CityDropdown extends StatelessWidget {
  final String label, value;
  final List<String> items;
  final void Function(String?) onChanged;
  const _CityDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF888888),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Color(0xFF888888),
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
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
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: const Color(0xFFFF6B35)),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
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
