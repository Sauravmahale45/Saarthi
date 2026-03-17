import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONFIG — swap these before release
// ─────────────────────────────────────────────────────────────────────────────
const _kRazorpayKeyId = 'rzp_live_R9zV5xSLAabRtZ'; // ← replace
const _kBackendBaseUrl =
    'https://payment-server-oi6b.onrender.com/api/payment'; // ← replace

// ─────────────────────────────────────────────────────────────────────────────
// PROFESSIONAL PALETTE (dark, clean, blue‑accented)
// ─────────────────────────────────────────────────────────────────────────────
// Background
const _bg = Color(0xFFF8FAFC); // very light gray

// Cards
const _surface = Colors.white;
const _surfaceAlt = Color(0xFFF1F5F9);

// Borders
const _border = Color(0xFFE2E8F0);

// Primary (Pay button)
const _primary = Color(0xFF3B82F6); // blue-500
const _primaryDeep = Color(0xFF2563EB); // blue-600
const _primaryLight = Color(0xFF60A5FA);

// Text
const _textPrimary = Color(0xFF0F172A); // dark slate
const _textSecondary = Color(0xFF475569);
const _textMuted = Color(0xFF94A3B8);

// Status
const _success = Color(0xFF10B981);
const _error = Color(0xFFEF4444);
// red‑500

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class PaymentScreen extends StatefulWidget {
  final String parcelId;
  final double price;
  final String fromCity;
  final String toCity;

  const PaymentScreen({
    super.key,
    required this.parcelId,
    required this.price,
    required this.fromCity,
    required this.toCity,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with TickerProviderStateMixin {
  late Razorpay _razorpay;

  // UI state
  bool _creatingOrder = false;
  bool _verifying = false;
  _PayStatus _status = _PayStatus.idle;
  String? _failureMsg;

  // Animations
  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _successCtrl;
  late AnimationController _shimmerCtrl;

  late Animation<double> _cardFade;
  late Animation<Offset> _card1Slide;
  late Animation<Offset> _card2Slide;
  late Animation<Offset> _btnSlide;
  late Animation<double> _btnFade;
  late Animation<double> _pulse;
  late Animation<double> _successScale;
  late Animation<double> _successFade;
  late Animation<double> _shimmer;

  // Total is now simply the parcel price (no fees)
  double get _total => widget.price;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initRazorpay();
    _entryCtrl.forward();
  }

  void _initAnimations() {
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    final easeOut = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutCubic,
    );

    _cardFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _card1Slide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryCtrl,
            curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
          ),
        );
    _card2Slide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryCtrl,
            curve: const Interval(0.15, 0.70, curve: Curves.easeOutCubic),
          ),
        );
    _btnSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryCtrl,
            curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    _btnFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.4, 0.9, curve: Curves.easeOut),
    );

    _pulse = Tween<double>(
      begin: 0.97,
      end: 1.03,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _successScale = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));
    _successFade = CurvedAnimation(parent: _successCtrl, curve: Curves.easeOut);
    _shimmer = _shimmerCtrl;
  }

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentFailure);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _successCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ── Step 1: Create Razorpay order via backend ──────────────────────────────
  Future<void> _initiatePayment() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _creatingOrder = true;
      _failureMsg = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_kBackendBaseUrl/create-order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': widget.price, 'parcelId': widget.parcelId}),
      );

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final orderId = data['orderId'] as String?;
      if (orderId == null || orderId.isEmpty) {
        throw Exception('Invalid order response from server.');
      }

      setState(() => _creatingOrder = false);
      _openRazorpayCheckout(orderId);
    } catch (e) {
      setState(() {
        _creatingOrder = false;
        _status = _PayStatus.failed;
        _failureMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Step 2: Open Razorpay checkout ─────────────────────────────────────────
  void _openRazorpayCheckout(String orderId) {
    final user = FirebaseAuth.instance.currentUser;
    final options = <String, dynamic>{
      'key': _kRazorpayKeyId,
      'order_id': orderId,
      'amount': (_total * 100).toInt(), // paise
      'name': 'Saarthi',
      'description': 'Parcel Payment — ${widget.fromCity} → ${widget.toCity}',
      'prefill': {
        'email': user?.email ?? '',
        'contact': user?.phoneNumber ?? '',
      },
      'theme': {'color': '#3B82F6'}, // professional blue
    };
    _razorpay.open(options);
  }

  // ── Step 3: Verify payment with backend ────────────────────────────────────
  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    HapticFeedback.heavyImpact();
    setState(() => _verifying = true);

    try {
      final verifyResponse = await http.post(
        Uri.parse('$_kBackendBaseUrl/verify-payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_order_id': response.orderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
          'parcelId': widget.parcelId,
        }),
      );

      if (verifyResponse.statusCode != 200) {
        throw Exception('Verification failed: ${verifyResponse.body}');
      }

      // ✅ Backend verified. Webhook will update Firestore — don't touch it here.
      setState(() {
        _verifying = false;
        _status = _PayStatus.success;
      });
      await _successCtrl.forward();

      // Auto-navigate back after 2.2s
      await Future.delayed(const Duration(milliseconds: 2200));
      if (mounted) context.pop();
    } catch (e) {
      setState(() {
        _verifying = false;
        _status = _PayStatus.failed;
        _failureMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onPaymentFailure(PaymentFailureResponse response) {
    HapticFeedback.vibrate();
    setState(() {
      _status = _PayStatus.failed;
      _failureMsg = response.message ?? 'Payment was cancelled or failed.';
    });
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _showSnack('Wallet selected: ${response.walletName}');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _error : _success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _resetAndRetry() {
    setState(() {
      _status = _PayStatus.idle;
      _failureMsg = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          _buildBgGlows(),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: _status == _PayStatus.success
                  ? _buildSuccessView()
                  : _status == _PayStatus.failed
                  ? _buildFailureView()
                  : _buildPayView(),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BACKGROUND
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBgGlows() => Positioned.fill(
    child: Stack(
      children: [
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 340,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_primary.withOpacity(0.12), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -100,
          left: -80,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_primaryLight.withOpacity(0.08), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN PAY VIEW (footer icons removed)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPayView() {
    final isBusy = _creatingOrder || _verifying;

    return Column(
      key: const ValueKey('pay'),
      children: [
        // ── AppBar ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _iconBtn(Icons.arrow_back_ios_new_rounded, () => context.pop()),
              const SizedBox(width: 12),
              const Text(
                'Parcel Payment',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _primary.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.shield_outlined, color: _primaryLight, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Secured',
                      style: TextStyle(
                        color: _primaryLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Route card ───────────────────────────────────────────────
                SlideTransition(
                  position: _card1Slide,
                  child: FadeTransition(
                    opacity: _cardFade,
                    child: _buildRouteCard(),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Price breakdown card (fees removed) ─────────────────────
                SlideTransition(
                  position: _card2Slide,
                  child: FadeTransition(
                    opacity: _cardFade,
                    child: _buildPriceCard(),
                  ),
                ),
                const SizedBox(height: 16),

                // (footer icons completely removed)
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),

        // ── Pay Now button (pinned bottom) ───────────────────────────────────
        SlideTransition(
          position: _btnSlide,
          child: FadeTransition(
            opacity: _btnFade,
            child: _buildPayButton(isBusy),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Route card ─────────────────────────────────────────────────────────────
  Widget _buildRouteCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: _primaryLight, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Parcel Route',
                style: TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ID: ${widget.parcelId.substring(0, 8)}…',
                  style: const TextStyle(
                    fontSize: 10,
                    color: _primaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // From
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FROM',
                      style: TextStyle(
                        fontSize: 10,
                        color: _textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.fromCity,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow with dotted line
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_primary, _primaryLight],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
              // To
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'TO',
                      style: TextStyle(
                        fontSize: 10,
                        color: _textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.toCity,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Price breakdown card (no fees, only total) ─────────────────────────────
  Widget _buildPriceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: _primaryLight,
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'Price Breakdown',
                style: TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _priceRow('Parcel delivery fee', widget.price),

          const SizedBox(height: 14),
          Container(height: 1, color: _border),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Payable',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) =>
                    Transform.scale(scale: _pulse.value, child: child),
                child: Text(
                  '₹${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: _primaryLight,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: _textSecondary),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }

  // ── Pay Now button ─────────────────────────────────────────────────────────
  Widget _buildPayButton(bool isBusy) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: isBusy ? null : _initiatePayment,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            gradient: isBusy
                ? LinearGradient(colors: [_surfaceAlt, _surfaceAlt])
                : const LinearGradient(
                    colors: [_primary, _primaryDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: isBusy
                ? []
                : [
                    BoxShadow(
                      color: _primary.withOpacity(0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Center(
            child: isBusy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: _primaryLight,
                          strokeWidth: 2.5,
                        ),
                      ),
                      SizedBox(width: 14),
                      Text(
                        'Processing…',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Pay ₹${_total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUCCESS VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSuccessView() {
    return Center(
      key: const ValueKey('success'),
      child: FadeTransition(
        opacity: _successFade,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _successScale,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_success, Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _success.withOpacity(0.45),
                        blurRadius: 40,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 62,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Payment Successful!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '₹${_total.toStringAsFixed(2)} paid for your parcel.',
                style: const TextStyle(fontSize: 15, color: _textSecondary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Redirecting you back…',
                style: TextStyle(fontSize: 13, color: _textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FAILURE VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildFailureView() {
    return Center(
      key: const ValueKey('fail'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _error.withOpacity(0.1),
                border: Border.all(color: _error.withOpacity(0.3), width: 2),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: _error,
                size: 50,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Payment Failed',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _failureMsg ?? 'Something went wrong. Please try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: _textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _resetAndRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text(
                  'Try Again',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text(
                'Go Back',
                style: TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  BoxDecoration _cardDeco() => BoxDecoration(
    color: _surface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: _border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.25),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Icon(icon, color: _textSecondary, size: 18),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
enum _PayStatus { idle, success, failed }
