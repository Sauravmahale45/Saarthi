import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'user_management_screen.dart';
import 'traveler_management_screen.dart';
import 'parcel_management_screen.dart';
import 'payment_management_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  // ---------------------------------------------------------------------------
  // AUTH
  // ---------------------------------------------------------------------------

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) context.go('/login');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sign out failed: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE STREAMS
  // ---------------------------------------------------------------------------

  Stream<int> _totalUsersStream() => FirebaseFirestore.instance
      .collection('users')
      .snapshots()
      .map((s) => s.docs.length);

  Stream<int> _travelersStream() => FirebaseFirestore.instance
      .collection('users')
      .where("role", isEqualTo: "traveler")
      .snapshots()
      .map((s) => s.docs.length);

  Stream<int> _parcelsStream() => FirebaseFirestore.instance
      .collection('parcels')
      .snapshots()
      .map((s) => s.docs.length);

  Stream<double> _revenueStream() => FirebaseFirestore.instance
      .collection('payments')
      .snapshots()
      .map((snapshot) {
        double total = 0.0;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (data is! Map<String, dynamic>) continue;
          final raw = data['amount'];
          if (raw is num) total += raw.toDouble();
        }
        return total;
      });

  // ---------------------------------------------------------------------------
  // STAT CARD
  //
  // Root: a plain Container that fills its GridView cell (no fixed height).
  // Column uses mainAxisSize.max + mainAxisAlignment.start so children stack
  // from the top and never try to overflow the cell boundary.
  // ---------------------------------------------------------------------------

  Widget _statCard(
    IconData icon,
    Color iconColor,
    Color bgColor,
    String number,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Color(0x14000000),
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        // FIX: start alignment — children never push past the cell bottom
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),

          const SizedBox(height: 8),

          // FIX: FittedBox scales the number down on narrow cards
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              number,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: 2),

          // FIX: Flexible + ellipsis keeps the label inside the cell
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps a count stream in a StreamBuilder with loading / error states.
  Widget _intStatCard({
    required Stream<int> stream,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String label,
  }) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        final value = snapshot.hasError
            ? "—"
            : snapshot.data?.toString() ?? "...";
        return _statCard(icon, iconColor, bgColor, value, label);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MODULE CARD
  //
  // Same pattern as _statCard: Column fills the cell top-down; both text
  // widgets are wrapped in Flexible so long strings never overflow.
  // ---------------------------------------------------------------------------

  Widget _moduleCard(
    BuildContext context,
    IconData icon,
    Color color,
    String title,
    String subtitle,
    Widget page,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              color: Color(0x14000000),
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          // FIX: start alignment — children never push past the cell bottom
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withAlpha(38), // ~15 % opacity
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),

            const SizedBox(height: 10),

            // FIX: Flexible prevents title from pushing the column taller
            // than the cell when it wraps to a second line
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),

            const SizedBox(height: 4),

            Flexible(
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF2D3A8C),
        elevation: 0,
        title: const Text("Saarthi Admin Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) {
              if (value == "logout") _signOut(context);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: "logout",
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 10),
                    Text("Sign Out"),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
        ],
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth > 600;
          final statColumns = isTablet ? 3 : 2;
          final moduleColumns = isTablet ? 3 : 2;

          // ----------------------------------------------------------------
          // FIX: Calculate childAspectRatio from the *actual* card width so
          // the cell is always tall enough for the content, on every device.
          //
          //   availableWidth = total width − horizontal padding − gap sum
          //   cardWidth      = availableWidth / columnCount
          //   ratio          = cardWidth / targetHeight
          //
          // Target heights (px) are chosen to comfortably fit all children:
          //   Stat card  : icon(40) + gap(8) + number(28) + gap(2) +
          //                label(36) + v-padding(28) = 142 → use 144
          //   Module card: icon(44) + gap(10) + title(40) + gap(4) +
          //                subtitle(32) + v-padding(28) = 158 → use 160
          // ----------------------------------------------------------------

          const double hPadding = 32.0; // 16 left + 16 right
          const double statTargetHeight = 144.0;
          const double moduleTargetHeight = 160.0;

          final double statSpacing = 12.0 * (statColumns - 1);
          final double moduleSpacing = 14.0 * (moduleColumns - 1);

          final double statCardWidth =
              (constraints.maxWidth - hPadding - statSpacing) / statColumns;
          final double moduleCardWidth =
              (constraints.maxWidth - hPadding - moduleSpacing) / moduleColumns;

          final double statRatio = statCardWidth / statTargetHeight;
          final double moduleRatio = moduleCardWidth / moduleTargetHeight;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Welcome back, Admin 👋",
                  style: TextStyle(color: Colors.grey),
                ),

                const SizedBox(height: 6),

                const Text(
                  "Overview",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 20),

                // ---- STATS GRID ----
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: statColumns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: statRatio, // FIX: width-derived ratio
                  ),
                  children: [
                    _intStatCard(
                      stream: _totalUsersStream(),
                      icon: Icons.people_outline,
                      iconColor: const Color(0xFF2D3A8C),
                      bgColor: const Color(0xFFE8EAF6),
                      label: "Total Users",
                    ),
                    _intStatCard(
                      stream: _travelersStream(),
                      icon: Icons.directions_bike,
                      iconColor: Colors.blue,
                      bgColor: const Color(0xFFE0F2FE),
                      label: "Travelers",
                    ),
                    _intStatCard(
                      stream: _parcelsStream(),
                      icon: Icons.inventory_2_outlined,
                      iconColor: Colors.orange,
                      bgColor: const Color(0xFFFFF7ED),
                      label: "Total Parcels",
                    ),
                    StreamBuilder<double>(
                      stream: _revenueStream(),
                      builder: (context, snapshot) {
                        final display = snapshot.hasError
                            ? "—"
                            : snapshot.data != null
                            ? "₹${snapshot.data!.toStringAsFixed(0)}"
                            : "...";
                        return _statCard(
                          Icons.currency_rupee,
                          Colors.green,
                          const Color(0xFFF0FDF4),
                          display,
                          "Revenue",
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                const Text(
                  "Admin Modules",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),

                // ---- MODULES GRID ----
                GridView.count(
                  crossAxisCount: moduleColumns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: moduleRatio, // FIX: width-derived ratio
                  children: [
                    _moduleCard(
                      context,
                      Icons.manage_accounts,
                      const Color(0xFF2D3A8C),
                      "User Management",
                      "Manage registered users",
                      const UserManagementScreen(),
                    ),
                    _moduleCard(
                      context,
                      Icons.delivery_dining,
                      Colors.blue,
                      "Traveler Management",
                      "Track active travelers",
                      const TravelerManagementScreen(),
                    ),
                    _moduleCard(
                      context,
                      Icons.local_shipping,
                      Colors.orange,
                      "Parcel Monitoring",
                      "Monitor deliveries",
                      const ParcelManagementScreen(),
                    ),
                    _moduleCard(
                      context,
                      Icons.payments,
                      Colors.green,
                      "Payment Management",
                      "Handle transactions",
                      const PaymentManagementScreen(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}
