// lib/features/splash/splash_screen.dart
//
// Saarthi — Splash + Onboarding
// • Pure white background throughout (splash + onboarding)
// • Medium-sized icons (no oversized hero icons)
// • Medium-sized buttons (compact, not full-width blocks)
// • Consistent light professional palette

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════════════════
//  DESIGN TOKENS
// ════════════════════════════════════════════════════════════════════════════

const _white = Colors.white;
const _bg = Color(0xFFF8FAFC); // very light grey-white
const _indigo = Color(0xFF4F46E5);
const _indigoLight = Color(0xFFEEF2FF); // indigo tint for chips/bg
const _indigoDark = Color(0xFF3730A3);
const _teal = Color(0xFF14B8A6);
const _tealLight = Color(0xFFCCFBF1);
const _tealDark = Color(0xFF0F766E);
const _orange = Color(0xFFF97316);
const _orangeLight = Color(0xFFFFEDD5);
const _orangeDark = Color(0xFFC2410C);
const _textPrimary = Color(0xFF0F172A);
const _textSecondary = Color(0xFF475569);
const _textMuted = Color(0xFF94A3B8);
const _border = Color(0xFFE2E8F0);
const _borderMid = Color(0xFFCBD5E1);

// ════════════════════════════════════════════════════════════════════════════
//  ONBOARDING DATA
// ════════════════════════════════════════════════════════════════════════════

class _OBPage {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Color accent;
  final Color accentLight;
  final Color accentDark;
  final IconData icon;

  const _OBPage({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.accentLight,
    required this.accentDark,
    required this.icon,
  });
}

const _pages = [
  _OBPage(
    eyebrow: 'FOR SENDERS',
    title: 'Send Anything,\nAnywhere',
    subtitle:
        'Connect with verified travelers heading your way. Fast, safe, and affordable parcel delivery across cities.',
    accent: _indigo,
    accentLight: _indigoLight,
    accentDark: _indigoDark,
    icon: Icons.inventory_2_rounded,
  ),
  _OBPage(
    eyebrow: 'FOR TRAVELERS',
    title: 'Earn While\nYou Travel',
    subtitle:
        'Heading to another city? Carry parcels along the way and earn extra income on every trip — zero extra effort.',
    accent: _teal,
    accentLight: _tealLight,
    accentDark: _tealDark,
    icon: Icons.flight_takeoff_rounded,
  ),
  _OBPage(
    eyebrow: 'REAL-TIME TRACKING',
    title: 'Track Every\nStep Live',
    subtitle:
        'GPS-powered live tracking, OTP-secured pickup, and instant delivery confirmation — total peace of mind.',
    accent: _orange,
    accentLight: _orangeLight,
    accentDark: _orangeDark,
    icon: Icons.radar_rounded,
  ),
];

// ════════════════════════════════════════════════════════════════════════════
//  AUTH ROUTING HELPER  (shared by splash + onboarding)
// ════════════════════════════════════════════════════════════════════════════

Future<void> _authRoute(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    context.go('/login');
    return;
  }
  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final d = snap.data() ?? {};
    final role = d['role'] as String? ?? '';
    final phone = d['phone'] as String? ?? '';
    final city = d['city'] as String? ?? '';

    if (!context.mounted) return;
    if (role.isEmpty) {
      context.go('/role');
    } else if (phone.isEmpty || city.isEmpty) {
      context.go('/profile_setup');
    } else {
      switch (role) {
        case 'admin':
          context.go('/admin_dashboard');
          break;
        case 'sender':
          context.go('/sender');
          break;
        case 'traveler':
          context.go('/traveler');
          break;
        default:
          context.go('/role');
      }
    }
  } catch (_) {
    if (context.mounted) context.go('/login');
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SPLASH SCREEN  — white background
// ════════════════════════════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _ringScale;
  late Animation<double> _ringOpacity;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;
  late Animation<double> _tagFade;
  late Animation<Offset> _tagSlide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _logoFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.60, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.50, curve: Curves.elasticOut),
      ),
    );

    _ringScale = Tween<double>(begin: 0.60, end: 1.6).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.05, 0.60, curve: Curves.easeOut),
      ),
    );
    _ringOpacity = Tween<double>(begin: 0.45, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.05, 0.60, curve: Curves.easeOut),
      ),
    );

    _textFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
          ),
        );

    _tagFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.50, 0.78, curve: Curves.easeOut),
    );
    _tagSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.50, 0.78, curve: Curves.easeOut),
          ),
        );

    _ctrl.forward();
    _decideNext();
  }

  Future<void> _decideNext() async {
    await Future.delayed(const Duration(milliseconds: 2400));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('saarthi_onboarding_done') ?? false;
    if (!done) {
      Navigator.of(
        context,
      ).pushReplacement(_FadeRoute(child: const OnboardingScreen()));
    } else {
      await _authRoute(context);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle dot-grid decoration
          CustomPaint(painter: _SplashBgPainter()),

          Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo + single expanding ring ──────────────────
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Expanding ring
                        Transform.scale(
                          scale: _ringScale.value,
                          child: Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _indigo.withOpacity(_ringOpacity.value),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        // Logo tile
                        FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: _indigo,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: _indigo.withOpacity(0.28),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  'सा',
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                    color: _white,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // App name
                  FadeTransition(
                    opacity: _textFade,
                    child: SlideTransition(
                      position: _textSlide,
                      child: const Text(
                        'Saarthi',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                          letterSpacing: 1.2,
                          height: 1,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Tagline
                  FadeTransition(
                    opacity: _tagFade,
                    child: SlideTransition(
                      position: _tagSlide,
                      child: const Text(
                        'Your travel. Their delivery.',
                        style: TextStyle(
                          fontSize: 14,
                          color: _textMuted,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 52),

                  // Loader dots
                  FadeTransition(opacity: _tagFade, child: const _WaveDots()),
                ],
              ),
            ),
          ),

          // Version
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Text(
              'v1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: _textMuted.withOpacity(0.6),
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ONBOARDING SCREEN  — white background, medium icons & buttons
// ════════════════════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _current = 0;

  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  late Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _buildAnim();
    _anim.forward();
  }

  void _buildAnim() {
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(
      parent: _anim,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _anim,
            curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
          ),
        );
    _iconScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _anim,
        curve: const Interval(0.1, 0.8, curve: Curves.elasticOut),
      ),
    );
  }

  Future<void> _toPage(int i) async {
    if (i >= _pages.length) return;
    await _anim.reverse();
    setState(() => _current = i);
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
    _anim.forward(from: 0);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('saarthi_onboarding_done', true);
    if (!mounted) return;
    await _authRoute(context);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_current];
    final isLast = _current == _pages.length - 1;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Light dot-grid background
          CustomPaint(painter: _OBBgPainter()),

          // Hidden swipe-only PageView
          PageView.builder(
            controller: _pageCtrl,
            itemCount: _pages.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) {
              if (i != _current) _toPage(i);
            },
            itemBuilder: (_, __) => const SizedBox.shrink(),
          ),

          // Illustration (upper half)
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: size.height * 0.08),
                    child: _buildIllustration(page),
                  ),
                ),
              ),
            ),
          ),

          // Content sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildSheet(page, isLast),
          ),

          // Skip button
          if (!isLast)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 20,
              child: GestureDetector(
                onTap: _finish,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Illustration ── medium icon (48 px), no oversized disc ───────────────

  Widget _buildIllustration(_OBPage page) {
    return AnimatedBuilder(
      animation: _iconScale,
      builder: (_, __) => Transform.scale(
        scale: _iconScale.value,
        child: SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Soft radial glow
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      page.accent.withOpacity(0.10),
                      page.accent.withOpacity(0.0),
                    ],
                  ),
                ),
              ),

              // Dashed ring
              CustomPaint(
                size: const Size(185, 185),
                painter: _DashedRingPainter(color: page.accent),
              ),

              // White ring (lift effect)
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _white,
                  boxShadow: [
                    BoxShadow(
                      color: page.accent.withOpacity(0.14),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              // Coloured inner disc — MEDIUM size
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: page.accentLight,
                  border: Border.all(
                    color: page.accent.withOpacity(0.18),
                    width: 1.5,
                  ),
                ),
              ),

              // Icon — MEDIUM size (36 px)
              Icon(page.icon, color: page.accent, size: 36),

              // Four small floating dots
              ..._dots(page.accent),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _dots(Color color) {
    const offsets = [
      Offset(-75, -46),
      Offset(74, -50),
      Offset(-78, 38),
      Offset(72, 44),
    ];
    const sz = [8.0, 6.0, 5.0, 7.0];
    return List.generate(
      4,
      (i) => Positioned(
        left: 110 + offsets[i].dx,
        top: 110 + offsets[i].dy,
        child: Container(
          width: sz[i],
          height: sz[i],
          decoration: BoxDecoration(
            color: color.withOpacity(0.55),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  // ── Bottom content sheet ──────────────────────────────────────────────────

  Widget _buildSheet(_OBPage page, bool isLast) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 28, 24, bottomPad + 24),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eyebrow
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: page.accentLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    page.eyebrow,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: page.accent,
                      letterSpacing: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Title
                Text(
                  page.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                    height: 1.2,
                    letterSpacing: -0.4,
                  ),
                ),

                // Accent bar
                const SizedBox(height: 8),
                Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: page.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),

                // Subtitle
                Text(
                  page.subtitle,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: _textSecondary,
                    height: 1.6,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 28),

                // Dots row + CTA button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Progress dots
                    Row(
                      children: List.generate(_pages.length, (i) {
                        final active = i == _current;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.only(right: 6),
                          width: active ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active ? page.accent : _borderMid,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const Spacer(),

                    // Medium CTA button
                    GestureDetector(
                      onTap: isLast ? _finish : () => _toPage(_current + 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: page.accent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: page.accent.withOpacity(0.30),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isLast ? 'Get Started' : 'Next',
                              style: const TextStyle(
                                color: _white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: _white,
                              size: 15,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PAINTERS
// ════════════════════════════════════════════════════════════════════════════

// Splash — subtle dot grid on white
class _SplashBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = _indigo.withOpacity(0.06)
      ..strokeWidth = 0;
    for (double y = 28; y < s.height; y += 36) {
      for (double x = 28; x < s.width; x += 36) {
        canvas.drawCircle(Offset(x, y), 1.4, p);
      }
    }
    // Soft arc — top right
    final arc = Paint()
      ..color = _indigo.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(s.width + 40, -40), s.width * 0.55, arc);
    canvas.drawCircle(Offset(s.width + 40, -40), s.width * 0.38, arc);
  }

  @override
  bool shouldRepaint(_) => false;
}

// Onboarding — same subtle dot grid on white
class _OBBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = _indigo.withOpacity(0.055);
    for (double y = 28; y < s.height * 0.55; y += 34) {
      for (double x = 28; x < s.width; x += 34) {
        canvas.drawCircle(Offset(x, y), 1.3, p);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// Dashed ring
class _DashedRingPainter extends CustomPainter {
  final Color color;
  const _DashedRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const dashes = 26;
    const gapRatio = 0.38;
    final r = size.width / 2;
    final cx = size.width / 2;
    final cy = size.height / 2;

    for (int i = 0; i < dashes; i++) {
      final start = (2 * math.pi / dashes) * i;
      final sweep = (2 * math.pi / dashes) * (1 - gapRatio);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ════════════════════════════════════════════════════════════════════════════
//  WAVE DOTS LOADER
// ════════════════════════════════════════════════════════════════════════════

class _WaveDots extends StatefulWidget {
  const _WaveDots();
  @override
  State<_WaveDots> createState() => _WaveDotsState();
}

class _WaveDotsState extends State<_WaveDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final phase = _ctrl.value - i * 0.18;
          final wave = math.sin(phase * 2 * math.pi).clamp(-1.0, 1.0);
          final yShift = wave * 4.5;
          final opacity = 0.25 + ((wave + 1) / 2) * 0.65;
          return Transform.translate(
            offset: Offset(0, yShift),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _indigo.withOpacity(opacity),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  FADE ROUTE
// ════════════════════════════════════════════════════════════════════════════

class _FadeRoute extends PageRouteBuilder {
  final Widget child;
  _FadeRoute({required this.child})
    : super(
        pageBuilder: (_, __, ___) => child,
        transitionsBuilder: (_, anim, __, ch) =>
            FadeTransition(opacity: anim, child: ch),
        transitionDuration: const Duration(milliseconds: 450),
      );
}
