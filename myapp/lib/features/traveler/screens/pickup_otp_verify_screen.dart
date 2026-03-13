import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Light theme professional color palette ─────────────────────────────────────
const _bg = Colors.white; // Pure white background
const _surface = Color(0xFFF8FAFC); // Light surface for cards
const _surfaceAlt = Color(0xFFF1F5F9); // Slightly darker for contrast
const _border = Color(0xFFE2E8F0); // Light grey border
const _borderFocus = Color(0xFF6366F1); // Indigo for focus
const _borderError = Color(0xFFEF4444); // Red for error
const _textPrimary = Color(0xFF0F172A); // Dark navy for main text
const _textSecondary = Color(0xFF64748B); // Muted grey for secondary
const _indigo = Color(0xFF4F46E5); // Primary indigo
const _indigoLight = Color(0xFF818CF8); // Lighter indigo
const _teal = Color(0xFF14B8A6); // Teal for regenerate
const _green = Color(0xFF22C55E); // Success green
const _red = Color(0xFFEF4444); // Error red

class PickupOTPVerifyScreen extends StatefulWidget {
  final String parcelId;
  const PickupOTPVerifyScreen({super.key, required this.parcelId});

  @override
  State<PickupOTPVerifyScreen> createState() => _PickupOTPVerifyScreenState();
}

class _PickupOTPVerifyScreenState extends State<PickupOTPVerifyScreen>
    with TickerProviderStateMixin {
  // OTP fields (four separate boxes)
  final List<TextEditingController> _controllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isRegenerating = false;
  bool _hasError = false;
  bool _showSuccess = false;

  // Animations
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

  @override
  void initState() {
    super.initState();

    // Entry animation
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

    // Shake on error
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shake = Tween<double>(begin: 0, end: 1).animate(_shakeController);

    // Success animation
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

    // Pulse on lock icon
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

  String _generateOTP() => (1000 + Random().nextInt(9000)).toString();

  Future<void> _regenerateOTP() async {
    setState(() => _isRegenerating = true);
    try {
      final otp = _generateOTP();
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({'pickupOTP': otp, 'pickupStarted': true});

      for (final c in _controllers) c.clear();
      _focusNodes[0].requestFocus();
      setState(() {
        _hasError = false;
        _isRegenerating = false;
      });

      _showSnack('🔄 New OTP generated & sent to sender!');
    } catch (e) {
      setState(() => _isRegenerating = false);
      _showSnack('Failed to regenerate OTP: $e', isError: true);
    }
  }

  Future<void> _cancelPickup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _CancelDialog(),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({'pickupOTP': null, 'pickupStarted': false});
      if (mounted) Navigator.of(context).pop(false);
    } catch (e) {
      _showSnack('Failed to cancel: $e', isError: true);
    }
  }

  Future<void> _verifyOTP() async {
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
      final doc = await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .get();

      final stored = doc.data()?['pickupOTP']?.toString() ?? '';

      if (entered != stored) {
        setState(() {
          _isVerifying = false;
          _hasError = true;
        });
        _triggerShake();
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
        _showSnack('❌ Wrong OTP. Please try again.', isError: true);
        return;
      }

      // Correct — update Firestore
      await FirebaseFirestore.instance
          .collection('parcels')
          .doc(widget.parcelId)
          .update({
            'status': 'picked',
            'pickupOTP': null,
            'pickupStarted': false,
            'pickedAt': FieldValue.serverTimestamp(),
          });

      setState(() {
        _isVerifying = false;
        _showSuccess = true;
      });
      HapticFeedback.heavyImpact();
      await _successController.forward();

      await Future.delayed(const Duration(milliseconds: 1600));
      if (mounted) Navigator.of(context).pop(true); // return true = verified
    } catch (e) {
      setState(() => _isVerifying = false);
      _showSnack('Verification failed: $e', isError: true);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg, // Pure white background
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _showSuccess ? _buildSuccessView() : _buildMainView(),
        ),
      ),
    );
  }

  // Main OTP view
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
            children: [
              Icon(Icons.lock_outline_rounded, color: _indigo, size: 13),
              const SizedBox(width: 5),
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
              BoxShadow(
                color: _indigo.withOpacity(0.2),
                blurRadius: 24,
                spreadRadius: 0,
              ),
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

  Widget _buildHeading() {
    return Column(
      children: [
        const Text(
          'Verify Pickup',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 4-digit OTP\nshared by the sender',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // OTP input boxes – light theme with proper spacing
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
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
              ), // 12px total spacing
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
                children: const [
                  Icon(Icons.error_outline_rounded, color: _red, size: 15),
                  SizedBox(width: 6),
                  Text(
                    'Incorrect OTP. Try again.',
                    style: TextStyle(
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

  Widget _buildSecondaryActions() {
    return Column(
      children: [
        // Regenerate OTP
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
        // Cancel pickup
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

  // Success view after OTP verification – light theme adjusted
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
                    BoxShadow(
                      color: _green.withOpacity(0.3),
                      blurRadius: 24,
                      spreadRadius: 0,
                    ),
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

// Individual OTP input box – light theme with proper styling
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

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() {
      setState(() => _isFocused = widget.focusNode.hasFocus);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.controller.text.isNotEmpty;
    final isError = widget.hasError;

    Color borderColor;
    if (isError)
      borderColor = _borderError;
    else if (_isFocused)
      borderColor = _borderFocus;
    else if (hasValue)
      borderColor = _indigo.withOpacity(0.5);
    else
      borderColor = _border;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: _indigo.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ]
            : [],
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: isError ? _red : _textPrimary,
        ),
        cursorColor: _indigo,
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(() {});
    super.dispose();
  }
}

// Cancel confirmation dialog – light theme
class _CancelDialog extends StatelessWidget {
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
              'This will reset the OTP and cancel the pickup process. You can restart it anytime.',
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
