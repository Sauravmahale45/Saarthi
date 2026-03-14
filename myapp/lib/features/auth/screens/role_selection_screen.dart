import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedRole;
  bool _isLoading = false;

  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _slideUp;

  @override
  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    _slideUp = Tween<double>(
      begin: 40,
      end: 0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward();

    // 🔥 Check role when page opens
    _checkExistingRole();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final role = doc.data()?['role'];

    if (!mounted) return;

    if (role == 'admin') {
      context.go('/admin_home');
    } else if (role == 'sender') {
      context.go('/sender');
    } else if (role == 'traveler') {
      context.go('/traveler');
    }
  }

  Future<void> _saveRoleAndProceed() async {
    if (_selectedRole == null) return;

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('User not logged in');

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': _selectedRole,
      });

      if (!mounted) return;

      if (_selectedRole == 'sender') {
        context.go('/sender');
      } else {
        context.go('/traveler');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fade,
              child: Transform.translate(
                offset: Offset(0, _slideUp.value),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),

                // ── Header ───────────────────────────────────────────
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'सा',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                const Text(
                  'How will you\nuse Saarthi?',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Pick your role to get started.\nYou can switch anytime from settings.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF888888),
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 40),

                // ── Sender Card ───────────────────────────────────────
                _RoleCard(
                  emoji: '📦',
                  title: 'Send a Parcel',
                  subtitle:
                      'I need to send something to another city quickly and affordably.',
                  role: 'sender',
                  accentColor: const Color(0xFF6366F1),
                  features: const [
                    'Post parcel in 2 minutes',
                    'Track in real-time',
                    'Pay only on delivery',
                  ],
                  selected: _selectedRole == 'sender',
                  onTap: () => setState(() => _selectedRole = 'sender'),
                ),

                const SizedBox(height: 16),

                // ── Traveler Card ─────────────────────────────────────
                _RoleCard(
                  emoji: '🚌',
                  title: 'Carry & Earn',
                  subtitle:
                      'I travel between cities and want to earn extra income on my trips.',
                  role: 'traveler',
                  accentColor: const Color(0xFF10B981),
                  features: const [
                    'Earn ₹200–₹500 per trip',
                    'Choose parcels on your route',
                    'Flexible — no fixed schedule',
                  ],
                  selected: _selectedRole == 'traveler',
                  onTap: () => setState(() => _selectedRole = 'traveler'),
                ),

                const Spacer(),

                // ── Continue Button ───────────────────────────────────
                AnimatedOpacity(
                  opacity: _selectedRole != null ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_selectedRole == null || _isLoading)
                          ? null
                          : _saveRoleAndProceed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        disabledBackgroundColor: const Color(0xFFFF6B35),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _selectedRole == null
                                      ? 'Select a role to continue'
                                      : 'Continue as ${_selectedRole == 'sender' ? 'Sender' : 'Traveler'}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_selectedRole != null) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Note ──────────────────────────────────────────────
                Center(
                  child: Text(
                    '🔒 Your data is safe and never shared without consent.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
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
}

// ── Role Card Widget ───────────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String role;
  final Color accentColor;
  final List<String> features;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.role,
    required this.accentColor,
    required this.features,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withOpacity(0.05)
              : const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accentColor : const Color(0xFFEEEEEE),
            width: selected ? 2 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accentColor.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row ────────────────────────────────────────────
            Row(
              children: [
                // Emoji box
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: selected
                        ? accentColor.withOpacity(0.12)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? accentColor.withOpacity(0.3)
                          : const Color(0xFFEEEEEE),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(width: 14),

                // Title + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: selected
                              ? accentColor
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF888888),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                // Check icon
                AnimatedScale(
                  scale: selected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),

            // ── Feature list (only when selected) ──────────────────
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: selected
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    Divider(color: accentColor.withOpacity(0.2), thickness: 1),
                    const SizedBox(height: 12),
                    ...features.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: accentColor,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              f,
                              style: TextStyle(
                                fontSize: 13,
                                color: accentColor.withOpacity(0.85),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
