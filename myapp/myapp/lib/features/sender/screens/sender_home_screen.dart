// lib/features/sender/sender_home_screen.dart
//
// Saarthi – Sender Home with persistent bottom navigation bar.
// Tabs: Home | My Parcels | Track | Support | Profile

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/features/auth/screens/login_signup_screen.dart';

// ── Design tokens ──────────────────────────────────────────────────────────
const primaryColor = Color(0xFF4F46E5);
const secondaryColor = Color(0xFF14B8A6);
const accentColor = Color(0xFFF97316);
const backgroundColor = Color(0xFFF8FAFC);
const textPrimary = Color(0xFF0F172A);
const textSecondary = Color(0xFF64748B);
const cardBorder = Color(0xFFE2E8F0);

const _kRequestExpiry = Duration(minutes: 15);

// ════════════════════════════════════════════════════════════════════════════
//  ROOT SHELL – owns the BottomNavigationBar and index state
// ════════════════════════════════════════════════════════════════════════════

class SenderHomeScreen extends StatefulWidget {
  const SenderHomeScreen({super.key});

  @override
  State<SenderHomeScreen> createState() => _SenderHomeScreenState();
}

class _SenderHomeScreenState extends State<SenderHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    _SenderDashboard(),
    _MyParcelsPage(),
    _TrackPage(),
    _SupportPage(),
    _ProfilePage(),
  ];

  void _onTabTapped(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: _SaarthiBottomNav(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  BOTTOM NAV BAR
// ════════════════════════════════════════════════════════════════════════════

class _SaarthiBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _SaarthiBottomNav({required this.currentIndex, required this.onTap});

  static const _items = [
    _NavItem(
      icon: Icons.home_rounded,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded,
      label: 'Parcels',
    ),
    _NavItem(
      icon: Icons.radar_rounded,
      activeIcon: Icons.radar_rounded,
      label: 'Track',
    ),
    _NavItem(
      icon: Icons.headset_mic_outlined,
      activeIcon: Icons.headset_mic_rounded,
      label: 'Support',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = i == currentIndex;
              return _NavTile(
                item: item,
                selected: selected,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? primaryColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                key: ValueKey(selected),
                color: selected ? primaryColor : textSecondary,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? primaryColor : textSecondary,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TAB 0 – DASHBOARD (original home content)
// ════════════════════════════════════════════════════════════════════════════

class _SenderDashboard extends StatefulWidget {
  const _SenderDashboard();

  @override
  State<_SenderDashboard> createState() => _SenderDashboardState();
}

class _SenderDashboardState extends State<_SenderDashboard> {
  final _user = FirebaseAuth.instance.currentUser;

  Stream<QuerySnapshot> get _parcelsStream => FirebaseFirestore.instance
      .collection('parcels')
      .where('senderId', isEqualTo: _user?.uid)
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots();

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    await googleSignIn.signOut();
    if (mounted) context.go('/login');
  }

  Map<String, List<QueryDocumentSnapshot>> _groupAndLimitParcels(
    List<QueryDocumentSnapshot> docs,
  ) {
    final pending = <QueryDocumentSnapshot>[];
    final active = <QueryDocumentSnapshot>[];
    final delivered = <QueryDocumentSnapshot>[];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      if (status == 'expired' || status == 'cancelled') continue;
      if (status == 'pending' || status == 'requested') {
        pending.add(doc);
      } else if (status == 'accepted' || status == 'picked') {
        active.add(doc);
      } else if (status == 'delivered') {
        delivered.add(doc);
      }
    }

    return {
      'pending': pending.take(5).toList(),
      'active': active.take(5).toList(),
      'delivered': delivered.take(3).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-parcel'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Send Parcel',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: RefreshIndicator(
        color: primaryColor,
        onRefresh: () async => setState(() {}),
        child: StreamBuilder<QuerySnapshot>(
          stream: _parcelsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingSkeleton();
            }
            if (snapshot.hasError) {
              return _ErrorState(
                error: snapshot.error.toString(),
                onRetry: () => setState(() {}),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _EmptyState(
                onSendTap: () => context.push('/create-parcel'),
              );
            }

            final parcels = _groupAndLimitParcels(snapshot.data!.docs);

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GreetingCard(user: _user),
                  const SizedBox(height: 20),
                  _StatsRow(parcels: parcels),
                  const SizedBox(height: 24),
                  _QuickActions(
                    onSendTap: () => context.push('/create-parcel'),
                  ),
                  const SizedBox(height: 24),
                  if (parcels['pending']!.isNotEmpty)
                    _ParcelSection(
                      title: 'Pending Requests',
                      parcels: parcels['pending']!,
                      seeAllRoute: '/sender-parcels?tab=pending',
                      maxCards: 5,
                    ),
                  if (parcels['active']!.isNotEmpty)
                    _ParcelSection(
                      title: 'Active Deliveries',
                      parcels: parcels['active']!,
                      seeAllRoute: '/sender-parcels?tab=active',
                      maxCards: 5,
                    ),
                  if (parcels['delivered']!.isNotEmpty)
                    _ParcelSection(
                      title: 'Recently Delivered',
                      parcels: parcels['delivered']!,
                      seeAllRoute: '/sender-parcels?tab=delivered',
                      maxCards: 3,
                    ),
                  const SizedBox(height: 100),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [primaryColor, Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text(
                'सा',
                style: TextStyle(
                  fontSize: 15,
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
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      actions: [
        Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_outlined,
                color: textPrimary,
              ),
              onPressed: () {},
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: const Text(
                  '0',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: () => _showProfileSheet(context),
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: primaryColor.withOpacity(0.15),
              backgroundImage: _user?.photoURL != null
                  ? NetworkImage(_user!.photoURL!)
                  : null,
              child: _user?.photoURL == null
                  ? Text(
                      (_user?.displayName ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
            CircleAvatar(
              radius: 36,
              backgroundColor: primaryColor.withOpacity(0.15),
              backgroundImage: _user?.photoURL != null
                  ? NetworkImage(_user!.photoURL!)
                  : null,
              child: _user?.photoURL == null
                  ? Text(
                      (_user?.displayName ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              _user?.displayName ?? 'Sender',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              _user?.email ?? '',
              style: const TextStyle(fontSize: 13, color: textSecondary),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '📦 Sender',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.swap_horiz_rounded,
                color: primaryColor,
              ),
              title: const Text('Switch to Traveler'),
              onTap: () {
                Navigator.pop(context);
                context.go('/traveler');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
              title: const Text(
                'Sign Out',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _signOut();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TAB 1 – MY PARCELS
// ════════════════════════════════════════════════════════════════════════════

class _MyParcelsPage extends StatefulWidget {
  const _MyParcelsPage();

  @override
  State<_MyParcelsPage> createState() => _MyParcelsPageState();
}

class _MyParcelsPageState extends State<_MyParcelsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _streamByStatuses(List<String> statuses) =>
      FirebaseFirestore.instance
          .collection('parcels')
          .where('senderId', isEqualTo: _uid)
          .where('status', whereIn: statuses)
          .orderBy('createdAt', descending: true)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'My Parcels',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: primaryColor,
          unselectedLabelColor: textSecondary,
          indicatorColor: primaryColor,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Active'),
            Tab(text: 'Delivered'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _ParcelList(stream: _streamByStatuses(['pending', 'requested'])),
          _ParcelList(stream: _streamByStatuses(['accepted', 'picked'])),
          _ParcelList(stream: _streamByStatuses(['delivered'])),
        ],
      ),
    );
  }
}

class _ParcelList extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  const _ParcelList({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingSkeleton();
        }
        if (snap.hasError) {
          return _ErrorState(error: snap.error.toString(), onRetry: () {});
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('📭', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text(
                  'No parcels here yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'They will appear once created',
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snap.data!.docs.length,
          itemBuilder: (_, i) => _ParcelCard(doc: snap.data!.docs[i]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TAB 2 – TRACK
// ════════════════════════════════════════════════════════════════════════════

class _TrackPage extends StatefulWidget {
  const _TrackPage();

  @override
  State<_TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<_TrackPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Track Parcel',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              style: const TextStyle(fontSize: 14, color: textPrimary),
              decoration: InputDecoration(
                hintText: 'Search by city or parcel ID…',
                hintStyle: const TextStyle(fontSize: 13, color: textSecondary),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: textSecondary,
                  size: 20,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: cardBorder, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: primaryColor, width: 2),
                ),
              ),
            ),
          ),

          // List of active / picked parcels
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('parcels')
                  .where('senderId', isEqualTo: uid)
                  .where('status', whereIn: ['accepted', 'picked'])
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const _LoadingSkeleton();
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🗺️', style: TextStyle(fontSize: 48)),
                        SizedBox(height: 12),
                        Text(
                          'No active deliveries',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Accepted or picked-up parcels appear here',
                          style: TextStyle(fontSize: 13, color: textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snap.data!.docs.where((doc) {
                  if (_query.isEmpty) return true;
                  final d = doc.data() as Map<String, dynamic>;
                  final from = (d['fromCity'] as String? ?? '').toLowerCase();
                  final to = (d['toCity'] as String? ?? '').toLowerCase();
                  final id = doc.id.toLowerCase();
                  final q = _query.toLowerCase();
                  return from.contains(q) || to.contains(q) || id.contains(q);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No parcels match your search',
                      style: TextStyle(fontSize: 14, color: textSecondary),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final d = doc.data() as Map<String, dynamic>;
                    return _TrackCard(doc: doc, data: d);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;
  const _TrackCard({required this.doc, required this.data});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? '';
    final isPicked = status == 'picked';

    return GestureDetector(
      onTap: () => context.push('/parcel-details/${doc.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: secondaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.radar_rounded,
                    color: secondaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            data['fromCity'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: textPrimary,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: textSecondary,
                            ),
                          ),
                          Text(
                            data['toCity'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data['travelerName'] ?? 'Traveler assigned',
                        style: const TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: secondaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: secondaryColor,
                    ),
                  ),
                ),
              ],
            ),
            if (isPicked) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/track/${doc.id}'),
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: const Text('View Live Map'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TAB 3 – SUPPORT
// ════════════════════════════════════════════════════════════════════════════

class _SupportPage extends StatelessWidget {
  const _SupportPage();

  static const _faqs = [
    _FAQ(
      q: 'How do I send a parcel?',
      a: 'Tap "Send Parcel" on the home screen, fill in pickup and drop details, set a price, and submit. Travelers who are travelling that route will be shown your request.',
    ),
    _FAQ(
      q: 'How does pricing work?',
      a: 'You set the price you are willing to pay. Travelers can accept or negotiate. Saarthi does not charge a platform fee during beta.',
    ),
    _FAQ(
      q: 'What if a traveler does not respond?',
      a: 'A request expires after 15 minutes. You will see a "Choose Another Traveler" option to reassign.',
    ),
    _FAQ(
      q: 'How do I track my parcel?',
      a: 'Once a traveler picks up your parcel the Track tab shows a live map. You get a notification when it is delivered.',
    ),
    _FAQ(
      q: 'Is my parcel insured?',
      a: 'Saarthi facilitates connections between senders and travelers. Insurance coverage details are shown at the time of booking.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Help & Support',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Contact card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [primaryColor, Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.headset_mic_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need help?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Our support team is available\n9 AM – 9 PM every day.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Quick actions
          Row(
            children: [
              _SupportAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Live Chat',
                color: secondaryColor,
                onTap: () {},
              ),
              const SizedBox(width: 12),
              _SupportAction(
                icon: Icons.email_outlined,
                label: 'Email Us',
                color: accentColor,
                onTap: () {},
              ),
              const SizedBox(width: 12),
              _SupportAction(
                icon: Icons.phone_outlined,
                label: 'Call Us',
                color: primaryColor,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 28),

          const Text(
            'Frequently Asked Questions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ..._faqs.map((f) => _FAQTile(faq: f)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SupportAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SupportAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FAQ {
  final String q, a;
  const _FAQ({required this.q, required this.a});
}

class _FAQTile extends StatefulWidget {
  final _FAQ faq;
  const _FAQTile({required this.faq});

  @override
  State<_FAQTile> createState() => _FAQTileState();
}

class _FAQTileState extends State<_FAQTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _open ? primaryColor.withOpacity(0.3) : cardBorder,
          width: _open ? 1.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ExpansionTile(
          onExpansionChanged: (v) => setState(() => _open = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          title: Text(
            widget.faq.q,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          iconColor: primaryColor,
          collapsedIconColor: textSecondary,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                widget.faq.a,
                style: const TextStyle(
                  fontSize: 13,
                  color: textSecondary,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TAB 4 – PROFILE
// ════════════════════════════════════════════════════════════════════════════

class _ProfilePage extends StatefulWidget {
  const _ProfilePage();

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  final _user = FirebaseAuth.instance.currentUser;

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    await googleSignIn.signOut();
    if (mounted) context.go('/login');
  }

  Future<DocumentSnapshot?> _fetchUserDoc() async {
    final uid = _user?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'My Profile',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: FutureBuilder<DocumentSnapshot?>(
        future: _fetchUserDoc(),
        builder: (context, snap) {
          final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
          final name = data['name'] as String? ?? _user?.displayName ?? 'User';
          final email = data['email'] as String? ?? _user?.email ?? '';
          final phone = data['phone'] as String? ?? '';
          final city = data['city'] as String? ?? '';

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Avatar + name
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: primaryColor.withOpacity(0.12),
                      backgroundImage: _user?.photoURL != null
                          ? NetworkImage(_user!.photoURL!)
                          : null,
                      child: _user?.photoURL == null
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '📦 Sender',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Info card
              _ProfileInfoCard(email: email, phone: phone, city: city),
              const SizedBox(height: 20),

              // Actions
              _ProfileAction(
                icon: Icons.edit_outlined,
                label: 'Edit Profile',
                color: primaryColor,
                onTap: () => context.push('/profile_setup'),
              ),
              _ProfileAction(
                icon: Icons.swap_horiz_rounded,
                label: 'Switch to Traveler',
                color: secondaryColor,
                onTap: () => context.go('/traveler'),
              ),
              _ProfileAction(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                color: accentColor,
                onTap: () {},
              ),
              _ProfileAction(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                color: Colors.red,
                onTap: _signOut,
                isDestructive: true,
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileInfoCard extends StatelessWidget {
  final String email, phone, city;
  const _ProfileInfoCard({
    required this.email,
    required this.phone,
    required this.city,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _InfoRow(icon: Icons.email_outlined, label: 'Email', value: email),
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: cardBorder,
          ),
          _InfoRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: phone.isEmpty ? 'Not set' : '+91 $phone',
          ),
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: cardBorder,
          ),
          _InfoRow(
            icon: Icons.location_city_rounded,
            label: 'City',
            value: city.isEmpty ? 'Not set' : city,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: textSecondary),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDestructive ? Colors.red.withOpacity(0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDestructive ? Colors.red.withOpacity(0.2) : cardBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDestructive ? Colors.red : textPrimary,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS (used by multiple tabs)
// ════════════════════════════════════════════════════════════════════════════

// ── Parcel Section ─────────────────────────────────────────────────────────
class _ParcelSection extends StatelessWidget {
  final String title;
  final List<QueryDocumentSnapshot> parcels;
  final String seeAllRoute;
  final int maxCards;

  const _ParcelSection({
    required this.title,
    required this.parcels,
    required this.seeAllRoute,
    required this.maxCards,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.push(seeAllRoute),
              child: const Text(
                'See All →',
                style: TextStyle(fontSize: 13, color: primaryColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...parcels.take(maxCards).map((doc) => _ParcelCard(doc: doc)),
      ],
    );
  }
}

// ── Parcel Card with Countdown ─────────────────────────────────────────────
class _ParcelCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  const _ParcelCard({required this.doc});

  @override
  State<_ParcelCard> createState() => _ParcelCardState();
}

class _ParcelCardState extends State<_ParcelCard> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  Map<String, dynamic> get data => widget.doc.data() as Map<String, dynamic>;
  String get status => data['status'] ?? '';
  bool get isRequested => status == 'requested';

  @override
  void initState() {
    super.initState();
    if (isRequested) _startTimer();
  }

  @override
  void didUpdateWidget(covariant _ParcelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldStatus = (oldWidget.doc.data() as Map<String, dynamic>)['status'];
    if (status == 'requested' && oldStatus != 'requested') {
      _startTimer();
    } else if (status != 'requested') {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    final requestedAt = data['requestedAt'] as Timestamp?;
    if (requestedAt == null) {
      _remaining = _kRequestExpiry;
      _expired = false;
    } else {
      final elapsed = DateTime.now().difference(requestedAt.toDate());
      if (elapsed >= _kRequestExpiry) {
        _remaining = Duration.zero;
        _expired = true;
        return;
      }
      _remaining = _kRequestExpiry - elapsed;
      _expired = false;
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final ts = data['requestedAt'] as Timestamp?;
      if (ts == null) {
        if (_remaining.inSeconds > 0) {
          setState(() => _remaining = _remaining - const Duration(seconds: 1));
        } else {
          setState(() => _expired = true);
          _timer?.cancel();
        }
      } else {
        final elapsed = DateTime.now().difference(ts.toDate());
        if (elapsed >= _kRequestExpiry) {
          setState(() {
            _remaining = Duration.zero;
            _expired = true;
          });
          _timer?.cancel();
        } else {
          setState(() => _remaining = _kRequestExpiry - elapsed);
        }
      }
    });
  }

  Color get statusColor {
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'requested':
        return accentColor;
      case 'accepted':
        return const Color(0xFF3B82F6);
      case 'picked':
        return primaryColor;
      case 'delivered':
        return secondaryColor;
      default:
        return textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/parcel-details/${widget.doc.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              data['fromCity'] ?? '',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: textSecondary,
                              ),
                            ),
                            Text(
                              data['toCity'] ?? '',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${data['description'] ?? 'Parcel'}  •  ${data['weight'] ?? 0} kg',
                          style: const TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (isRequested) ...[
                const SizedBox(height: 12),
                _RequestCountdown(
                  remaining: _remaining,
                  expired: _expired,
                  travelerName: data['travelerName'] ?? 'Traveler',
                  parcelId: widget.doc.id,
                ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1, color: cardBorder),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.currency_rupee,
                        size: 14,
                        color: secondaryColor,
                      ),
                      Text(
                        '${data['price'] ?? 0}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: secondaryColor,
                        ),
                      ),
                    ],
                  ),
                  const Row(
                    children: [
                      Text(
                        'Tap to see details',
                        style: TextStyle(fontSize: 12, color: primaryColor),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 11,
                        color: primaryColor,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Request Countdown ──────────────────────────────────────────────────────
class _RequestCountdown extends StatelessWidget {
  final Duration remaining;
  final bool expired;
  final String travelerName;
  final String parcelId;

  const _RequestCountdown({
    required this.remaining,
    required this.expired,
    required this.travelerName,
    required this.parcelId,
  });

  double get progress =>
      (remaining.inSeconds / _kRequestExpiry.inSeconds).clamp(0.0, 1.0);
  Color get timerColor {
    if (expired) return textSecondary;
    if (progress > 0.5) return secondaryColor;
    if (progress > 0.25) return accentColor;
    return Colors.red;
  }

  String get countdownLabel {
    if (expired) return 'Expired';
    final m = remaining.inMinutes;
    final s = remaining.inSeconds % 60;
    if (m > 0) return '$m min ${s.toString().padLeft(2, '0')} sec';
    return '${s}s left';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: timerColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: timerColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                expired
                    ? Icons.timer_off_outlined
                    : Icons.hourglass_top_rounded,
                size: 14,
                color: timerColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  expired
                      ? 'No response from $travelerName'
                      : 'Waiting for $travelerName to respond',
                  style: TextStyle(
                    fontSize: 12,
                    color: timerColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: timerColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  countdownLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: timerColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: timerColor.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(timerColor),
            ),
          ),
          const SizedBox(height: 6),
          if (expired)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push('/available-travelers/$parcelId'),
                style: TextButton.styleFrom(
                  foregroundColor: primaryColor,
                  padding: EdgeInsets.zero,
                ),
                child: const Text(
                  'Choose Another Traveler',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            Text(
              'Request auto-cancels if traveler doesn\'t respond in time.',
              style: TextStyle(
                fontSize: 10,
                color: timerColor.withOpacity(0.8),
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Greeting Card ──────────────────────────────────────────────────────────
class _GreetingCard extends StatelessWidget {
  final User? user;
  const _GreetingCard({required this.user});

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryColor, Color(0xFF818CF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_greeting 👋',
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            user?.displayName?.split(' ').first ?? 'Sender',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  'Send parcels across India',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Row ──────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final Map<String, List<QueryDocumentSnapshot>> parcels;
  const _StatsRow({required this.parcels});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
          label: 'Pending',
          value: '${parcels['pending']?.length ?? 0}',
          color: accentColor,
          icon: Icons.hourglass_empty_rounded,
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Active',
          value: '${parcels['active']?.length ?? 0}',
          color: primaryColor,
          icon: Icons.local_shipping_rounded,
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Delivered',
          value: '${parcels['delivered']?.length ?? 0}',
          color: secondaryColor,
          icon: Icons.check_circle_rounded,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick Actions ──────────────────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  final VoidCallback onSendTap;
  const _QuickActions({required this.onSendTap});

  @override
  Widget build(BuildContext context) {
    final actions = [
      {
        'icon': Icons.send_rounded,
        'label': 'Send\nParcel',
        'color': primaryColor,
        'onTap': onSendTap,
      },
      {
        'icon': Icons.track_changes,
        'label': 'Track\nParcel',
        'color': secondaryColor,
        'onTap': () {},
      },
      {
        'icon': Icons.history_rounded,
        'label': 'Order\nHistory',
        'color': accentColor,
        'onTap': () {},
      },
      {
        'icon': Icons.support_agent,
        'label': 'Support',
        'color': Colors.purple,
        'onTap': () {},
      },
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions.map((a) {
        final color = a['color'] as Color;
        return GestureDetector(
          onTap: a['onTap'] as VoidCallback,
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Icon(a['icon'] as IconData, color: color, size: 26),
              ),
              const SizedBox(height: 6),
              Text(
                a['label'] as String,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Empty / Error / Loading ────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onSendTap;
  const _EmptyState({required this.onSendTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📦', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'No parcels yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the button below to send your first parcel with Saarthi',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onSendTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Send First Parcel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2),
        ),
      ),
    );
  }
}
