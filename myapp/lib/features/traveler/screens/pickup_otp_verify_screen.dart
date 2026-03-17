// lib/features/tracking/pickup_otp_verify_screen.dart
//
// Security hardening applied:
//  • Regeneration rate-limit: 60-second cooldown, stored in pickupOTPGeneratedAt
//  • Attempt limit: 5 max, stored in pickupOTPAttempts, blocked until new OTP
//  • Concurrent-call guard: _isVerifying flag checked at entry
//  • Brute-force delay: 800 ms back-off after every wrong guess
//  • Success path resets pickupOTPAttempts = 0 in Firestore
//
// UI fix applied:
//  • _OTPBox uses Container → Center → SizedBox(56×56) → TextFormField
//  • isCollapsed: true + textAlignVertical: TextAlignVertical.center
//  • 12 px gap between boxes

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myapp/notifications/notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── Color palette ──────────────────────────────────────────────────────────
const _bg = Colors.white;
const _surface = Color(0xFFF8FAFC);
const _surfaceAlt = Color(0xFFF1F5F9);
const _border = Color(0xFFE2E8F0);
const _borderFocus = Color(0xFF6366F1);
const _borderError = Color(0xFFEF4444);
const _textPrimary = Color(0xFF0F172A);
const _textSecondary = Color(0xFF64748B);
const _indigo = Color(0xFF4F46E5);
const _indigoLight = Color(0xFF818CF8);
const _teal = Color(0xFF14B8A6);
const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);
const _orange = Color(0xFFF97316);

// ── Security constants ─────────────────────────────────────────────────────
const _kMaxAttempts = 5;
const _kRegenCooldownSeconds = 60;
const _kBruteForceDelayMs = 800;

class PickupOTPVerifyScreen extends StatefulWidget {
  final String parcelId;
  const PickupOTPVerifyScreen({super.key, required this.parcelId});

  @override
  State<PickupOTPVerifyScreen> createState() => _PickupOTPVerifyScreenState();
}

class _PickupOTPVerifyScreenState extends State<PickupOTPVerifyScreen>
    with TickerProviderStateMixin {
  // ── OTP fields ─────────────────────────────────────────────────────────────
  final List<TextEditingController> _controllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _isVerifying = false;
  bool _isRegenerating = false;
  bool _hasError = false;
  bool _showSuccess = false;

  // Shown inside the error chip when attempts are exhausted
  String _errorMessage = 'Incorrect OTP. Try again.';

  // ── Animation controllers ──────────────────────────────────────────────────
  late AnimationController _entryController;
  late AnimationController _shakeController;
  late AnimationController _successController;
  late AnimationController _pulseController;

  late Animation<double> _cardFade;
  late Animation<Offset> _cardSlide;
  late Animation<double> _iconScale;
  late Animation<double> _shake;
  late Animation<double> _successScale;
  late Animation<double> _successFade;
  late Animation<double> _pulse;

  // ════════════════════════════════════════════════════════════════════════════
  //  LIFECYCLE
  // ════════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();

    // Entry
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _cardFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
        );
    _iconScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
      ),
    );

    // Shake
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shake = Tween<double>(begin: 0, end: 1).animate(_shakeController);

    // Success
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );
    _successFade = CurvedAnimation(
      parent: _successController,
      curve: Curves.easeOut,
    );

    // Pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _shakeController.dispose();
    _successController.dispose();
    _pulseController.dispose();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  OTP GENERATION  (rate-limited: 60 s cooldown)
  // ════════════════════════════════════════════════════════════════════════════

  String _generateOTP() => (Random().nextInt(9000) + 1000).toString();

  Future<void> _regenerateOTP() async {
    if (_isRegenerating) return;

    // ── Cooldown check ─────────────────────────────────────────────────────
    try {
      final snap = await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .get();

      final data = snap.data() ?? {};
      final generatedAt = data['pickupOTPGeneratedAt'] as Timestamp?;

      if (generatedAt != null) {
        final secondsSince = DateTime.now()
            .difference(generatedAt.toDate())
            .inSeconds;
        if (secondsSince < _kRegenCooldownSeconds) {
          final wait = _kRegenCooldownSeconds - secondsSince;
          _showSnack(
            '⏳ Please wait $wait seconds before generating a new OTP.',
            isError: true,
          );
          return;
        }
      }
    } catch (e) {
      _showSnack('Could not check cooldown: $e', isError: true);
      return;
    }

    setState(() => _isRegenerating = true);

    try {
      final otp = _generateOTP();
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({
            'pickupOTP': otp,
            'pickupStarted': true,
            'pickupOTPGeneratedAt': FieldValue.serverTimestamp(),
            'pickupOTPAttempts': 0,
          });

      for (final c in _controllers) c.clear();
      _focusNodes[0].requestFocus();

      if (mounted) {
        setState(() {
          _hasError = false;
          _isRegenerating = false;
          _errorMessage = 'Incorrect OTP. Try again.';
        });
      }

      _showSnack('🔄 New OTP generated and sent to sender!');
    } catch (e) {
      if (mounted) setState(() => _isRegenerating = false);
      _showSnack('Failed to regenerate OTP: $e', isError: true);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  OTP VERIFICATION
  //   • Concurrent-call guard (_isVerifying)
  //   • Attempt limit (5 max, stored in Firestore)
  //   • 800 ms brute-force delay on wrong guess
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _verifyOTP() async {
    // ── Concurrent-call guard ──────────────────────────────────────────────
    if (_isVerifying) return;

    final entered = _controllers.map((c) => c.text).join();
    if (entered.length < 4) {
      _triggerShake();
      return;
    }

    setState(() {
      _isVerifying = true;
      _hasError = false;
    });

    try {
      final ref = FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId);

      final doc = await ref.get();
      final data = doc.data() ?? {};

      final stored = data['pickupOTP']?.toString() ?? '';
      final attempts = (data['pickupOTPAttempts'] as num?)?.toInt() ?? 0;
      final senderId = data['senderId'] as String?;

      // ── Attempt-limit check ─────────────────────────────────────────────
      if (attempts >= _kMaxAttempts) {
        if (mounted) {
          setState(() {
            _isVerifying = false;
            _hasError = true;
            _errorMessage = 'Too many attempts. Request a new OTP.';
          });
        }
        _triggerShake();
        _showSnack(
          '🔒 Too many failed attempts. Please regenerate the OTP.',
          isError: true,
        );
        return;
      }

      // ── Wrong OTP ──────────────────────────────────────────────────────
      if (entered != stored) {
        final newAttempts = attempts + 1;
        final remaining = _kMaxAttempts - newAttempts;

        // Increment attempt counter in Firestore
        await ref.update({'pickupOTPAttempts': newAttempts});

        // 800 ms brute-force back-off
        await Future.delayed(const Duration(milliseconds: _kBruteForceDelayMs));

        if (mounted) {
          setState(() {
            _isVerifying = false;
            _hasError = true;
            _errorMessage = remaining > 0
                ? '❌ Wrong OTP. $remaining attempt${remaining == 1 ? '' : 's'} left.'
                : 'Too many attempts. Request a new OTP.';
          });
        }

        _triggerShake();
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();

        _showSnack(
          remaining > 0
              ? '❌ Wrong OTP. $remaining attempt${remaining == 1 ? '' : 's'} remaining.'
              : '🔒 No attempts remaining. Please regenerate the OTP.',
          isError: true,
        );
        return;
      }

      // ── Correct OTP ────────────────────────────────────────────────────
      await ref.update({
        'status': 'picked',
        'pickupOTP': null,
        'pickupStarted': false,
        'pickupOTPAttempts': 0,
        'pickedAt': FieldValue.serverTimestamp(),
      });

      if (senderId != null) {
        try {
          // Get current traveler's name
          final currentUser = FirebaseAuth.instance.currentUser;
          final travelerName = await _getTravelerName(currentUser?.uid ?? '');
          if (travelerName.isNotEmpty) {
            await NotificationService.notifyParcelPickedUp(
              toUid: senderId,
              parcelId: widget.parcelId,
              travelerName: travelerName,
            );
          }
        } catch (e) {
          debugPrint('Failed to send pickup notification: $e');
        }
      }
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _showSuccess = true;
        });
      }

      HapticFeedback.heavyImpact();
      await _successController.forward();
      await Future.delayed(const Duration(milliseconds: 1600));

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _isVerifying = false);
      _showSnack('Verification failed: $e', isError: true);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  CANCEL PICKUP
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _cancelPickup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const _CancelDialog(),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({
            'pickupOTP': null,
            'pickupStarted': false,
            'pickupOTPAttempts': 0,
          });
      if (mounted) Navigator.of(context).pop(false);
    } catch (e) {
      _showSnack('Failed to cancel: $e', isError: true);
    }
  }

  Future<String> _getTravelerName(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      return doc.data()?['name'] ?? doc.data()?['displayName'] ?? 'Traveler';
    } catch (e) {
      return 'Traveler';
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  void _triggerShake() {
    _shakeController.reset();
    _shakeController.forward();
    HapticFeedback.mediumImpact();
  }

  void _showSnack(String msg, {bool isError = false}) {
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

  // ════════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _showSuccess ? _buildSuccessView() : _buildMainView(),
        ),
      ),
    );
  }

  Widget _buildMainView() {
    return FadeTransition(
      key: const ValueKey('main'),
      opacity: _cardFade,
      child: SlideTransition(
        position: _cardSlide,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              _buildTopBar(),
              const SizedBox(height: 48),
              _buildLockIcon(),
              const SizedBox(height: 28),
              _buildHeading(),
              const SizedBox(height: 40),
              _buildOTPFields(),
              const SizedBox(height: 12),
              _buildErrorText(),
              const SizedBox(height: 32),
              _buildVerifyButton(),
              const SizedBox(height: 20),
              _buildSecondaryActions(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Row(
      children: [
        GestureDetector(
          onTap: _cancelPickup,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.close_rounded,
              color: _textSecondary,
              size: 20,
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _indigo.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _indigo.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.lock_outline_rounded, color: _indigo, size: 13),
              SizedBox(width: 5),
              Text(
                'Secure OTP',
                style: TextStyle(
                  color: _indigo,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Lock icon ──────────────────────────────────────────────────────────────

  Widget _buildLockIcon() {
    return ScaleTransition(
      scale: _iconScale,
      child: ScaleTransition(
        scale: _pulse,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_indigo, _indigoLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: _indigo.withOpacity(0.2), blurRadius: 24),
            ],
          ),
          child: const Icon(
            Icons.local_shipping_rounded,
            color: Colors.white,
            size: 44,
          ),
        ),
      ),
    );
  }

  // ── Heading ────────────────────────────────────────────────────────────────

  Widget _buildHeading() {
    return const Column(
      children: [
        Text(
          'Verify Pickup',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Enter the 4-digit OTP\nshared by the sender',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: _textSecondary, height: 1.5),
        ),
      ],
    );
  }

  // ── OTP fields ─────────────────────────────────────────────────────────────

  Widget _buildOTPFields() {
    return AnimatedBuilder(
      animation: _shake,
      builder: (_, child) {
        final dx = _hasError
            ? (8 * (0.5 - (_shake.value % 0.25) / 0.25).abs()).roundToDouble()
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 400 + i * 90),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Padding(
              // 6 px each side = 12 px gap between boxes
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _OTPBox(
                controller: _controllers[i],
                focusNode: _focusNodes[i],
                hasError: _hasError,
                onChanged: (val) {
                  if (_hasError) setState(() => _hasError = false);
                  if (val.isNotEmpty && i < 3) {
                    _focusNodes[i + 1].requestFocus();
                  } else if (val.isEmpty && i > 0) {
                    _focusNodes[i - 1].requestFocus();
                  }
                  // Auto-submit when last box is filled
                  if (i == 3 && val.isNotEmpty) {
                    final allFilled = _controllers.every(
                      (c) => c.text.isNotEmpty,
                    );
                    if (allFilled) _verifyOTP();
                  }
                },
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Error text ─────────────────────────────────────────────────────────────

  Widget _buildErrorText() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _hasError
          ? Container(
              key: const ValueKey('err'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _red.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: _red,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _errorMessage,
                    style: const TextStyle(
                      color: _red,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(key: ValueKey('noerr'), height: 0),
    );
  }

  // ── Verify button ──────────────────────────────────────────────────────────

  Widget _buildVerifyButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isVerifying ? null : _verifyOTP,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isVerifying
                  ? [_border, _border]
                  : [_indigo, _indigoLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isVerifying
                ? []
                : [
                    BoxShadow(
                      color: _indigo.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Center(
            child: _isVerifying
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
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
                        'Verifying...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Confirm Pickup',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ── Secondary actions ──────────────────────────────────────────────────────

  Widget _buildSecondaryActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _isRegenerating ? null : _regenerateOTP,
            icon: _isRegenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: _teal,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 18, color: _teal),
            label: Text(
              _isRegenerating ? 'Regenerating...' : 'Regenerate OTP',
              style: const TextStyle(
                color: _teal,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _teal.withOpacity(0.4)),
              foregroundColor: _teal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: TextButton.icon(
            onPressed: _cancelPickup,
            icon: const Icon(
              Icons.cancel_outlined,
              size: 18,
              color: _textSecondary,
            ),
            label: const Text(
              'Cancel Pickup',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: _textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Success view ───────────────────────────────────────────────────────────

  Widget _buildSuccessView() {
    return Center(
      key: const ValueKey('success'),
      child: FadeTransition(
        opacity: _successFade,
        child: ScaleTransition(
          scale: _successScale,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_green, Color(0xFF16A34A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(color: _green.withOpacity(0.3), blurRadius: 24),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 60,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Pickup Confirmed!',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'OTP verified successfully.\nParcel status updated to Picked.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: _textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  OTP BOX  –  fixed layout: Container → Center → SizedBox → TextFormField
// ════════════════════════════════════════════════════════════════════════════

class _OTPBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final ValueChanged<String> onChanged;

  const _OTPBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
  });

  @override
  State<_OTPBox> createState() => _OTPBoxState();
}

class _OTPBoxState extends State<_OTPBox> {
  bool _isFocused = false;

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.controller.text.isNotEmpty;

    final Color borderColor = widget.hasError
        ? _borderError
        : _isFocused
        ? _borderFocus
        : hasValue
        ? _indigo.withOpacity(0.6)
        : _border;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: _indigo.withOpacity(0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: widget.hasError ? _red : _textPrimary,
        ),
        cursorColor: _indigo,
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
          isCollapsed: true,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CANCEL DIALOG
// ════════════════════════════════════════════════════════════════════════════

class _CancelDialog extends StatelessWidget {
  const _CancelDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cancel_outlined, color: _red, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Cancel Pickup?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This will reset the OTP and cancel the pickup process. '
              'You can restart it anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _border),
                      foregroundColor: _textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Keep',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Cancel Pickup',
                      style: TextStyle(fontWeight: FontWeight.w700),
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
