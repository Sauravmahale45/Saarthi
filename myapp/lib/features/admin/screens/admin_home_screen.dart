import 'package:flutter/material.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0;

  final List<_StatCard> _stats = const [
    _StatCard(
      label: 'Total Users',
      value: '1,284',
      icon: Icons.people_alt_rounded,
      color: Color(0xFF6C63FF),
    ),
    _StatCard(
      label: 'Active Sessions',
      value: '342',
      icon: Icons.bar_chart_rounded,
      color: Color(0xFF00C9A7),
    ),
    _StatCard(
      label: 'Pending Orders',
      value: '58',
      icon: Icons.receipt_long_rounded,
      color: Color(0xFFFF6B6B),
    ),
    _StatCard(
      label: 'Revenue Today',
      value: '₹24,500',
      icon: Icons.currency_rupee_rounded,
      color: Color(0xFFFFA94D),
    ),
  ];

  final List<_ActivityItem> _recentActivity = const [
    _ActivityItem(
      title: 'New user registered',
      subtitle: 'Priya Sharma joined 5 mins ago',
      icon: Icons.person_add_alt_1_rounded,
      color: Color(0xFF6C63FF),
    ),
    _ActivityItem(
      title: 'Order #1042 placed',
      subtitle: 'Ravi Kumar • ₹1,200',
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFF00C9A7),
    ),
    _ActivityItem(
      title: 'Report generated',
      subtitle: 'Monthly summary exported',
      icon: Icons.insert_drive_file_rounded,
      color: Color(0xFFFFA94D),
    ),
    _ActivityItem(
      title: 'Server alert resolved',
      subtitle: 'High CPU usage normalised',
      icon: Icons.check_circle_rounded,
      color: Color(0xFF00C9A7),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF6C63FF),
              child: const Text(
                'A',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Panel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  'Welcome back, Admin',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A8FA3),
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: Color(0xFF1A1A2E),
                ),
                onPressed: () {},
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6B6B),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overview heading
            const Text(
              'Overview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Today\'s snapshot at a glance',
              style: TextStyle(fontSize: 13, color: Color(0xFF8A8FA3)),
            ),
            const SizedBox(height: 16),

            // Stats Grid
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
              children: _stats
                  .map((stat) => _StatCardWidget(stat: stat))
                  .toList(),
            ),

            const SizedBox(height: 28),

            // Quick Actions
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _QuickActionButton(
                  label: 'Add User',
                  icon: Icons.person_add_rounded,
                  color: const Color(0xFF6C63FF),
                  onTap: () {},
                ),
                const SizedBox(width: 12),
                _QuickActionButton(
                  label: 'Reports',
                  icon: Icons.bar_chart_rounded,
                  color: const Color(0xFF00C9A7),
                  onTap: () {},
                ),
                const SizedBox(width: 12),
                _QuickActionButton(
                  label: 'Settings',
                  icon: Icons.settings_rounded,
                  color: const Color(0xFFFFA94D),
                  onTap: () {},
                ),
                const SizedBox(width: 12),
                _QuickActionButton(
                  label: 'Logs',
                  icon: Icons.list_alt_rounded,
                  color: const Color(0xFFFF6B6B),
                  onTap: () {},
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Recent Activity
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    'See all',
                    style: TextStyle(
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentActivity.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  indent: 60,
                  endIndent: 16,
                  color: Color(0xFFF0F1F5),
                ),
                itemBuilder: (context, index) {
                  final item = _recentActivity[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: item.color.withOpacity(0.12),
                      child: Icon(item.icon, color: item.color, size: 20),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    subtitle: Text(
                      item.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A8FA3),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFCBCDD6),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFF6C63FF).withOpacity(0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_rounded),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ── Data models ──────────────────────────────────────────────────────────────

class _StatCard {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _ActivityItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _ActivityItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _StatCardWidget extends StatelessWidget {
  final _StatCard stat;

  const _StatCardWidget({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: stat.color.withOpacity(0.12),
            child: Icon(stat.icon, color: stat.color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: stat.color,
                ),
              ),
              Text(
                stat.label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF8A8FA3)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
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
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
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
