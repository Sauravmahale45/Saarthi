import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
final GoogleSignIn googleSignIn = GoogleSignIn();

// ════════════════════════════════════════════════════════════════════════════
//  CENTRALIZED AUTH ROUTING  (reused across login, signup, google)
// ════════════════════════════════════════════════════════════════════════════

/// Reads Firestore users/{uid}, creates doc if missing, then routes to the
/// correct screen based on role completeness.
Future<void> navigateAfterAuth(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final fireUser = FirebaseAuth.instance.currentUser!;
  final ref = FirebaseFirestore.instance.collection('users').doc(uid);
  final snap = await ref.get();

  /// Create user doc if not exists
  if (!snap.exists) {
    await ref.set({
      'name': fireUser.displayName ?? '',
      'email': fireUser.email ?? '',
      'phone': '',
      'city': '',
      'photoUrl': fireUser.photoURL ?? '',
      'role': '',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  final data = (await ref.get()).data() ?? {};

  if (!context.mounted) return;

  final role = (data['role'] as String?) ?? '';
  final phone = (data['phone'] as String?) ?? '';
  final city = (data['city'] as String?) ?? '';

  /// ADMIN → DIRECT DASHBOARD
  if (role == 'admin') {
    context.go('/admin_dashboard');
    return;
  }

  /// No role selected
  if (role.isEmpty) {
    context.go('/role');
    return;
  }

  /// Profile incomplete
  if (phone.isEmpty || city.isEmpty) {
    context.go('/profile_setup');
    return;
  }

  /// Go to role home
  _routeToHome(context, role);
}

void _routeToHome(BuildContext context, String role) {
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

// ════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════════════════════

class LoginSignupScreen extends StatefulWidget {
  const LoginSignupScreen({super.key});

  @override
  State<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

class _LoginSignupScreenState extends State<LoginSignupScreen>
    with TickerProviderStateMixin {
  int _tabIndex = 0; // 0 = Login, 1 = Sign Up

  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _signupEmailCtrl = TextEditingController();
  final _signupPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscureLogin = true;
  bool _obscureSignup = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeIn);
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _switchTab(int index) {
    setState(() => _tabIndex = index);
    _slideCtrl.forward(from: 0);
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _error : _success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  // ── Email Login ────────────────────────────────────────────────────────────

  Future<void> _login() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (mounted) await navigateAfterAuth(context);
    } on FirebaseAuthException catch (e) {
      _showSnack(_friendlyError(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Email Sign Up ──────────────────────────────────────────────────────────

  Future<void> _signup() async {
    if (!_signupFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _signupEmailCtrl.text.trim(),
        password: _signupPasswordCtrl.text,
      );
      await cred.user?.updateDisplayName(_nameCtrl.text.trim());

      // Create Firestore document (navigateAfterAuth will merge if needed)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
            'name': _nameCtrl.text.trim(),
            'email': _signupEmailCtrl.text.trim(),
            'phone': '',
            'city': '',
            'photoUrl': '',
            'role': '',
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) await navigateAfterAuth(context);
    } on FirebaseAuthException catch (e) {
      _showSnack(_friendlyError(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Google Sign-In ─────────────────────────────────────────────────────────

  Future<void> _googleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCred.user!;

      // Merge base fields – navigateAfterAuth will check for role / phone / city
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) await navigateAfterAuth(context);
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      _showSnack('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Forgot Password ────────────────────────────────────────────────────────

  Future<void> _forgotPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      _showSnack('Enter your email first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailCtrl.text.trim(),
      );
      _showSnack('Reset link sent to your email!', isError: false);
    } catch (_) {
      _showSnack('Failed to send reset email.');
    }
  }

  // ── Validators ─────────────────────────────────────────────────────────────

  String? _validateEmail(String? v) {
    if (v == null || v.isEmpty) return 'Email is required';
    if (!v.contains('@')) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Minimum 6 characters';
    return null;
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    return null;
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Try again.';
      case 'email-already-in-use':
        return 'Email already registered. Please login.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please try later.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              _buildLogo(),
              const SizedBox(height: 28),
              _buildHeading(),
              const SizedBox(height: 24),
              _buildTabBar(),
              const SizedBox(height: 24),
              SlideTransition(
                position: _slideAnim,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: _tabIndex == 0
                      ? _buildLoginForm()
                      : _buildSignupForm(),
                ),
              ),
              const SizedBox(height: 24),
              _buildDivider(),
              const SizedBox(height: 20),
              _GoogleButton(isLoading: _isLoading, onTap: _googleSignIn),
              const SizedBox(height: 20),
              _buildSwitchHint(),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sub-builders ───────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primary, Color(0xFF6D28D9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _primary.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'सा',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'Saarthi',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: _text1,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tabIndex == 0 ? 'Welcome back 👋' : 'Create account 🚀',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _text1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _tabIndex == 0
              ? 'Sign in to continue your journey'
              : 'Join Saarthi and start earning or sending',
          style: const TextStyle(fontSize: 13.5, color: _text2),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _TabButton(
            label: 'Login',
            selected: _tabIndex == 0,
            onTap: () => _switchTab(0),
          ),
          _TabButton(
            label: 'Sign Up',
            selected: _tabIndex == 1,
            onTap: () => _switchTab(1),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: _border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ),
        const Expanded(child: Divider(color: _border)),
      ],
    );
  }

  Widget _buildSwitchHint() {
    return Center(
      child: GestureDetector(
        onTap: () => _switchTab(_tabIndex == 0 ? 1 : 0),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 13, color: _text2),
            children: [
              TextSpan(
                text: _tabIndex == 0
                    ? "Don't have an account? "
                    : 'Already have an account? ',
              ),
              TextSpan(
                text: _tabIndex == 0 ? 'Sign Up' : 'Login',
                style: const TextStyle(
                  color: _primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Login Form ─────────────────────────────────────────────────────────────

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          _AuthField(
            controller: _emailCtrl,
            label: 'Email address',
            hint: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          _AuthField(
            controller: _passwordCtrl,
            label: 'Password',
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            obscure: _obscureLogin,
            suffixIcon: _VisibilityToggle(
              obscure: _obscureLogin,
              onToggle: () => setState(() => _obscureLogin = !_obscureLogin),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _forgotPassword,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Forgot password?',
                style: TextStyle(
                  fontSize: 13,
                  color: _primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _PrimaryButton(label: 'Login', isLoading: _isLoading, onTap: _login),
        ],
      ),
    );
  }

  // ── Sign Up Form ───────────────────────────────────────────────────────────

  Widget _buildSignupForm() {
    return Form(
      key: _signupFormKey,
      child: Column(
        children: [
          _AuthField(
            controller: _nameCtrl,
            label: 'Full name',
            hint: 'Rohit Sharma',
            icon: Icons.person_outline_rounded,
            validator: _validateName,
          ),
          const SizedBox(height: 14),
          _AuthField(
            controller: _signupEmailCtrl,
            label: 'Email address',
            hint: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          _AuthField(
            controller: _signupPasswordCtrl,
            label: 'Password',
            hint: 'Min. 6 characters',
            icon: Icons.lock_outline_rounded,
            obscure: _obscureSignup,
            suffixIcon: _VisibilityToggle(
              obscure: _obscureSignup,
              onToggle: () => setState(() => _obscureSignup = !_obscureSignup),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 14),
          _AuthField(
            controller: _confirmPasswordCtrl,
            label: 'Confirm password',
            hint: 'Re-enter password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscureConfirm,
            suffixIcon: _VisibilityToggle(
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            validator: (v) {
              if (v != _signupPasswordCtrl.text)
                return 'Passwords do not match';
              return _validatePassword(v);
            },
          ),
          const SizedBox(height: 22),
          _PrimaryButton(
            label: 'Create Account',
            isLoading: _isLoading,
            onTap: _signup,
          ),
          const SizedBox(height: 14),
          Text(
            'By signing up you agree to our Terms of Service\nand Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[400],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  REUSABLE WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _primary.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? _primary : _text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: _text1),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 19, color: _text2),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(fontSize: 13, color: _text2),
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey[300]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _border, width: 1.2),
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
      ),
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  final bool obscure;
  final VoidCallback onToggle;

  const _VisibilityToggle({required this.obscure, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: _text2,
      ),
      onPressed: onToggle,
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _primary.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          shadowColor: _primary.withOpacity(0.4),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _GoogleButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(painter: _GoogleIconPainter()),
            ),
            const SizedBox(width: 12),
            const Text(
              'Continue with Google',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _text1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    void arc(Color c, double start, double sweep) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start,
        sweep,
        true,
        Paint()..color = c,
      );
    }

    arc(const Color(0xFF4285F4), -1.57, 1.57);
    arc(const Color(0xFF34A853), 0.00, 1.57);
    arc(const Color(0xFFFBBC05), 1.57, 0.79);
    arc(const Color(0xFFEA4335), 2.36, 0.79);
    arc(const Color(0xFFEA4335), -1.57, 0.79);
    canvas.drawCircle(Offset(cx, cy), r * 0.55, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_) => false;
}
