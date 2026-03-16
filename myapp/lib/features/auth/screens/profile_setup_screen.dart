// lib/features/auth/profile_setup_screen.dart
//
// Saarthi – Profile Setup screen.
// Collects: full name, phone number (10 digits), city.
// On submit → writes to Firestore users/{uid} then routes based on role.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────
const _primary = Color(0xFF4F46E5);
const _teal = Color(0xFF14B8A6);
const _orange = Color(0xFFF97316);
const _bg = Color(0xFFF8FAFC);
const _text1 = Color(0xFF0F172A);
const _text2 = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _error = Color(0xFFEF4444);
const _success = Color(0xFF22C55E);

// ════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════════════════════

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  bool _isLoading = false;
  bool _namePrefilled = false;

  late AnimationController _entranceCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fadeAnim = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.07),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut));
    _entranceCtrl.forward();

    _prefillFromFirebase();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  /// Pre-fills name and phone from Firestore if already partially set.
  Future<void> _prefillFromFirebase() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!snap.exists || snap.data() == null) return;

    final data = snap.data()!;
    final name = (data['name'] as String?) ?? '';
    final phone = (data['phone'] as String?) ?? '';
    final city = (data['city'] as String?) ?? '';

    if (mounted) {
      setState(() {
        if (name.isNotEmpty) {
          _nameCtrl.text = name;
          _namePrefilled = true;
        }
        if (phone.isNotEmpty) _phoneCtrl.text = phone;
        if (city.isNotEmpty) _cityCtrl.text = city;
      });
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Not authenticated');

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
      }, SetOptions(merge: true));

      // Read role to decide destination
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final role = (snap.data()?['role'] as String?) ?? '';

      if (!mounted) return;

      switch (role) {
        case 'sender':
          context.go('/sender');
          break;
        case 'traveler':
          context.go('/traveler');
          break;
        case 'admin':
          context.go('/admin_dashboard');
          break;
        default:
          context.go('/role');
      }
    } catch (e) {
      debugPrint('ProfileSetupScreen: submit error – $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save profile. Please try again.'),
            backgroundColor: _error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Validators ─────────────────────────────────────────────────────────────

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    return null;
  }

  String? _validatePhone(String? v) {
    if (v == null || v.isEmpty) return 'Phone number is required';
    if (!RegExp(r'^\d{10}$').hasMatch(v.trim())) {
      return 'Enter a valid 10-digit phone number';
    }
    return null;
  }

  String? _validateCity(String? v) {
    if (v == null || v.trim().isEmpty) return 'City is required';
    return null;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 36),
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildStepIndicator(),
                  const SizedBox(height: 28),
                  _buildFormCard(),
                  const SizedBox(height: 24),
                  _buildSubmitButton(),
                  const SizedBox(height: 16),
                  _buildPrivacyNote(),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo badge
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primary, Color(0xFF6D28D9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _primary.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'सा',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Almost there! 🎉',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _text1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Complete your profile so senders and\ntravelers can connect with you.',
          style: TextStyle(fontSize: 13.5, color: _text2, height: 1.5),
        ),
      ],
    );
  }

  // ── Step indicator ─────────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _StepDot(label: '1', title: 'Account', done: true),
        _StepConnector(filled: true),
        _StepDot(label: '2', title: 'Role', done: true),
        _StepConnector(filled: true),
        _StepDot(label: '3', title: 'Profile', done: false, active: true),
      ],
    );
  }

  // ── Form card ──────────────────────────────────────────────────────────────

  Widget _buildFormCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section label
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Your details',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _text1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Full name
            _ProfileField(
              controller: _nameCtrl,
              label: 'Full name',
              hint: 'Rohit Sharma',
              icon: Icons.person_outline_rounded,
              validator: _validateName,
              readOnly: _namePrefilled,
              helperText: _namePrefilled ? 'From your account' : null,
            ),
            const SizedBox(height: 16),

            // Phone
            _ProfileField(
              controller: _phoneCtrl,
              label: 'Phone number',
              hint: '9876543210',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: _validatePhone,
              prefixText: '+91  ',
            ),
            const SizedBox(height: 16),

            // City
            _ProfileField(
              controller: _cityCtrl,
              label: 'City',
              hint: 'Mumbai',
              icon: Icons.location_city_rounded,
              validator: _validateCity,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
      ),
    );
  }

  // ── Submit button ──────────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _primary.withOpacity(0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.check_circle_outline_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Save & Continue',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 13, color: Colors.grey[400]),
        const SizedBox(width: 5),
        Text(
          'Your information is private and secure.',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  REUSABLE WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool readOnly;
  final String? helperText;
  final String? prefixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;

  const _ProfileField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.readOnly = false,
    this.helperText,
    this.prefixText,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      textCapitalization: textCapitalization,
      style: TextStyle(fontSize: 14, color: readOnly ? _text2 : _text1),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        helperStyle: const TextStyle(
          fontSize: 11,
          color: _teal,
          fontStyle: FontStyle.italic,
        ),
        prefixIcon: Icon(icon, size: 19, color: _text2),
        prefixText: prefixText,
        prefixStyle: const TextStyle(
          fontSize: 14,
          color: _text2,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: readOnly ? const Color(0xFFF8FAFC) : Colors.white,
        labelStyle: const TextStyle(fontSize: 13, color: _text2),
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey[300]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(
            color: readOnly ? const Color(0xFFF1F5F9) : _border,
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        suffixIcon: readOnly
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.check_rounded, color: _teal, size: 18),
              )
            : null,
      ),
    );
  }
}

// ── Step indicator components ──────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  final String label;
  final String title;
  final bool done;
  final bool active;

  const _StepDot({
    required this.label,
    required this.title,
    this.done = false,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = done || active ? _primary : _border;
    final Color fg = done || active ? Colors.white : _text2;

    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: done ? _primary : (active ? Colors.white : _border),
            shape: BoxShape.circle,
            border: active ? Border.all(color: _primary, width: 2) : null,
            boxShadow: active || done
                ? [
                    BoxShadow(
                      color: _primary.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? _primary : _text2,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: done || active ? _primary : _text2,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool filled;
  const _StepConnector({this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
        decoration: BoxDecoration(
          color: filled ? _primary.withOpacity(0.3) : _border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
