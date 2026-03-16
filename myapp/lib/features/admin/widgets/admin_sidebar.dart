import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../screens/admin_dashboard.dart';
import '../screens/user_management_screen.dart';
import '../screens/traveler_management_screen.dart';
import '../screens/parcel_management_screen.dart';
import '../screens/payment_management_screen.dart';

class AdminSidebar extends StatelessWidget {
  const AdminSidebar({super.key});

  /// ---------------- LOGOUT ----------------

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (context.mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [

          /// ---------------- HEADER ----------------

          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, bottom: 30),
            decoration: const BoxDecoration(
              color: Color(0xFF2D3E91),
            ),
            child: const Column(
              children: [

                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.admin_panel_settings,
                    color: Color(0xFF2D3E91),
                    size: 30,
                  ),
                ),

                SizedBox(height: 12),

                Text(
                  "Saarthi Admin",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                SizedBox(height: 4),

                Text(
                  "Admin Panel",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          /// ---------------- MENU ----------------

          sidebarItem(
            context,
            icon: Icons.dashboard,
            title: "Dashboard",
            page: const AdminDashboard(),
          ),

          sidebarItem(
            context,
            icon: Icons.people,
            title: "Users",
            page: const UserManagementScreen(),
          ),

          sidebarItem(
            context,
            icon: Icons.delivery_dining,
            title: "Travelers",
            page: const TravelerManagementScreen(),
          ),

          sidebarItem(
            context,
            icon: Icons.inventory,
            title: "Parcels",
            page: const ParcelManagementScreen(),
          ),

          sidebarItem(
            context,
            icon: Icons.payments,
            title: "Payments",
            page: const PaymentManagementScreen(),
          ),

          const Spacer(),

          const Divider(),

          /// ---------------- LOGOUT ----------------

          ListTile(
            leading: const Icon(
              Icons.logout,
              color: Colors.red,
            ),
            title: const Text(
              "Logout",
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            onTap: () => _logout(context),
          ),

          const SizedBox(height: 10)
        ],
      ),
    );
  }

  /// ---------------- SIDEBAR ITEM ----------------

  Widget sidebarItem(
      BuildContext context, {
        required IconData icon,
        required String title,
        required Widget page,
      }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF2D3E91)),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      onTap: () {

        Navigator.pop(context);

        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => page),
        );
      },
    );
  }
}