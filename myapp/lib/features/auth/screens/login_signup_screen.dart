import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:go_router/go_router.dart';

class LoginSignupScreen extends StatefulWidget {
  const LoginSignupScreen({super.key});

  @override
  State<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

class _LoginSignupScreenState extends State<LoginSignupScreen>
    with TickerProviderStateMixin {
  // ── Tab (Login / Sign Up) ──────────────────────────────────────────────────
  int _tabIndex = 0; // 0 = Login, 1 = Sign Up

  // ── Form ──────────────────────────────────────────────────────────────────
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

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
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
    _fadeCtrl.forward(from: 0);
  }

  void _showSnack(String msg, {bool isError = true}) {
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

  Future<void> _navigateAfterAuth() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final role = doc.data()?['role'] as String?;

    if (!mounted) return;

    if (role == 'admin') {
      context.go('/admin_home');
    } else if (role == 'sender') {
      context.go('/sender');
    } else if (role == 'traveler') {
      context.go('/traveler');
    } else {
      context.go('/role');
    }
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
      await _navigateAfterAuth();
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
      // Update display name
      await cred.user?.updateDisplayName(_nameCtrl.text.trim());

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
            'name': _nameCtrl.text.trim(),
            'email': _signupEmailCtrl.text.trim(),
            'photoUrl': '',
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      context.go('/role');
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
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final user = userCred.user!;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _navigateAfterAuth();
    } catch (e) {
      _showSnack('Google sign-in failed. Try again.');
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
    } catch (e) {
      _showSnack('Failed to send reset email.');
    }
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

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),

              // ── Logo ──────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Center(
                      child: Text(
                        'सा',
                        style: TextStyle(
                          fontSize: 20,
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
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ── Title ─────────────────────────────────────────────
              Text(
                _tabIndex == 0 ? 'Welcome back 👋' : 'Create account 🚀',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _tabIndex == 0
                    ? 'Sign in to continue your journey'
                    : 'Join Saarthi and start earning or sending',
                style: const TextStyle(fontSize: 14, color: Color(0xFF888888)),
              ),

              const SizedBox(height: 28),

              // ── Tab Switcher ──────────────────────────────────────
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
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
              ),

              const SizedBox(height: 28),

              // ── Forms ─────────────────────────────────────────────
              FadeTransition(
                opacity: _fadeAnim,
                child: _tabIndex == 0 ? _buildLoginForm() : _buildSignupForm(),
              ),

              const SizedBox(height: 24),

              // ── Divider ───────────────────────────────────────────
              Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or continue with',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                  const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
                ],
              ),

              const SizedBox(height: 20),

              // ── Google Button ─────────────────────────────────────
              _GoogleButton(isLoading: _isLoading, onTap: _googleSignIn),

              const SizedBox(height: 20),

              // ── Switch tab hint ───────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () => _switchTab(_tabIndex == 0 ? 1 : 0),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF888888),
                      ),
                      children: [
                        TextSpan(
                          text: _tabIndex == 0
                              ? "Don't have an account? "
                              : 'Already have an account? ',
                        ),
                        TextSpan(
                          text: _tabIndex == 0 ? 'Sign Up' : 'Login',
                          style: const TextStyle(
                            color: Color(0xFFFF6B35),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
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
          // Email
          _InputField(
            controller: _emailCtrl,
            label: 'Email address',
            hint: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),

          // Password
          _InputField(
            controller: _passwordCtrl,
            label: 'Password',
            hint: '••••••••',
            icon: Icons.lock_outline,
            obscure: _obscureLogin,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureLogin
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: const Color(0xFF888888),
              ),
              onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 8),

          // Forgot password
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
                  color: Color(0xFFFF6B35),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Login button
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
          // Full name
          _InputField(
            controller: _nameCtrl,
            label: 'Full name',
            hint: 'Rohit Sharma',
            icon: Icons.person_outline,
            validator: _validateName,
          ),
          const SizedBox(height: 14),

          // Email
          _InputField(
            controller: _signupEmailCtrl,
            label: 'Email address',
            hint: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),

          // Password
          _InputField(
            controller: _signupPasswordCtrl,
            label: 'Password',
            hint: 'Min. 6 characters',
            icon: Icons.lock_outline,
            obscure: _obscureSignup,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureSignup
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: const Color(0xFF888888),
              ),
              onPressed: () => setState(() => _obscureSignup = !_obscureSignup),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 14),

          // Confirm password
          _InputField(
            controller: _confirmPasswordCtrl,
            label: 'Confirm password',
            hint: 'Re-enter password',
            icon: Icons.lock_outline,
            obscure: _obscureConfirm,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: const Color(0xFF888888),
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            validator: (v) {
              if (v != _signupPasswordCtrl.text)
                return 'Passwords do not match';
              return _validatePassword(v);
            },
          ),
          const SizedBox(height: 20),

          // Sign up button
          _PrimaryButton(
            label: 'Create Account',
            isLoading: _isLoading,
            onTap: _signup,
          ),

          const SizedBox(height: 12),

          // Terms
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

// ── Reusable Widgets ───────────────────────────────────────────────────────────

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
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
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
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFFFF6B35)
                    : const Color(0xFF888888),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _InputField({
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
      style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF888888)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFCCCCCC)),
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
          vertical: 16,
        ),
      ),
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
          backgroundColor: const Color(0xFFFF6B35),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
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
          border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google G icon (colored circles)
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
                color: Color(0xFF1A1A1A),
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
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w / 2;

    void arc(Color c, double start, double sweep) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start,
        sweep,
        true,
        Paint()..color = c,
      );
    }

    arc(const Color(0xFF4285F4), -1.57, 1.57); // Blue top
    arc(const Color(0xFF34A853), 0.00, 1.57); // Green right
    arc(const Color(0xFFFBBC05), 1.57, 0.79); // Yellow bottom-right
    arc(const Color(0xFFEA4335), 2.36, 0.79); // Red bottom-left
    arc(const Color(0xFFEA4335), -1.57, 0.79); // Red top-left

    // White center
    canvas.drawCircle(Offset(cx, cy), r * 0.55, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_) => false;
}
