import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  String? _selectedRoleFilter;

  final CollectionReference _users = FirebaseFirestore.instance.collection(
    'users',
  );

  // ---------------------------------------------------------------------------
  // FIRESTORE ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _blockUser(String uid, bool currentStatus) async {
    try {
      await _users.doc(uid).update({'isBlocked': !currentStatus});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update user: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDelete(String uid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _users.doc(uid).delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete user: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // DATA EXTRACTION
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _safeData(QueryDocumentSnapshot doc) {
    final Map<String, dynamic> raw =
        (doc.data() as Map<String, dynamic>?) ?? {};

    return {
      'name': raw['name'] is String && (raw['name'] as String).isNotEmpty
          ? raw['name'] as String
          : 'Unknown User',
      'email': raw['email'] is String && (raw['email'] as String).isNotEmpty
          ? raw['email'] as String
          : 'N/A',
      'phone': raw['phone'] is String && (raw['phone'] as String).isNotEmpty
          ? raw['phone'] as String
          : 'N/A',
      'role': raw['role'] is String && (raw['role'] as String).isNotEmpty
          ? raw['role'] as String
          : 'User',
      'city': raw['city'] is String && (raw['city'] as String).isNotEmpty
          ? raw['city'] as String
          : 'Not specified',
      'kycVerified': raw['kycVerified'] == true,
      'rating': raw['rating'] is num ? (raw['rating'] as num).toDouble() : 0.0,
      'createdAt': raw['createdAt'] is Timestamp ? raw['createdAt'] : null,
      'photoUrl': raw['photoUrl'] is String ? raw['photoUrl'] as String : null,
      'isBlocked': raw['isBlocked'] == true,
    };
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    return DateFormat.yMMMd().add_jm().format(timestamp.toDate());
  }

  // ---------------------------------------------------------------------------
  // PROFILE DRAWER (slides from left)
  // ---------------------------------------------------------------------------

  void _showUserDrawer(Map<String, dynamic> userData, String uid) {
    showGeneralDialog(
      context: context,
      barrierLabel: "User Profile",
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        // Align the dialog to the left edge of the screen
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8, // drawer width
              height: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with avatar and name
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00695C).withOpacity(0.1),
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundImage: userData['photoUrl'] != null
                                ? NetworkImage(userData['photoUrl'] as String)
                                : null,
                            backgroundColor: const Color(0xFFB2DFDB),
                            child: userData['photoUrl'] == null
                                ? Text(
                                    _initials(userData['name']),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF00695C),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userData['name'],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF004D40),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  userData['email'],
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Details list
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        children: [
                          _drawerDetailRow(
                            Icons.phone,
                            'Phone',
                            userData['phone'],
                          ),
                          _drawerDetailRow(
                            Icons.badge,
                            'Role',
                            userData['role'],
                          ),
                          _drawerDetailRow(
                            Icons.location_city,
                            'City',
                            userData['city'],
                          ),
                          _drawerDetailRow(
                            Icons.verified,
                            'KYC Verified',
                            userData['kycVerified'] ? 'Yes' : 'No',
                            valueColor: userData['kycVerified']
                                ? Colors.green
                                : Colors.red,
                          ),
                          _drawerDetailRow(
                            Icons.star,
                            'Rating',
                            userData['rating'].toString(),
                          ),
                          _drawerDetailRow(
                            Icons.calendar_today,
                            'Joined',
                            _formatDate(userData['createdAt']),
                          ),
                          if (userData['isBlocked'] as bool)
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: Text(
                                '⛔ Blocked User',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Close button
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Close'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF00695C),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0), // start from left
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  Widget _drawerDetailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF00695C)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // USER CARD (modern, full‑width, smaller buttons)
  // ---------------------------------------------------------------------------

  Widget _userCard(QueryDocumentSnapshot doc) {
    final String uid = doc.id;
    final Map<String, dynamic> data = _safeData(doc);

    final String name = data['name'] as String;
    final String email = data['email'] as String;
    final String phone = data['phone'] as String;
    final String role = data['role'] as String;
    final bool isBlocked = data['isBlocked'] as bool;
    final double rating = data['rating'] as double;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8), // only vertical spacing
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFB2DFDB),
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00695C),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF004D40),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: role.toLowerCase() == 'traveler'
                                ? const Color(0xFFE0F2F1)
                                : role.toLowerCase() == 'sender'
                                ? const Color(0xFFE8F5E9)
                                : const Color(0xFFF3E5F5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: role.toLowerCase() == 'traveler'
                                  ? const Color(0xFF00695C)
                                  : role.toLowerCase() == 'sender'
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFF7B1FA2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.circle,
                          size: 6,
                          color: isBlocked ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isBlocked ? 'Blocked' : 'Active',
                          style: TextStyle(
                            fontSize: 11,
                            color: isBlocked ? Colors.red : Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            phone,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.email_outlined,
                          size: 12,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            email,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          // Smaller action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.person_outline, size: 14),
                  label: const Text('Profile', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE0F2F1),
                    foregroundColor: const Color(0xFF00695C),
                    minimumSize: const Size(double.infinity, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _showUserDrawer(data, uid),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.block, size: 14),
                  label: Text(
                    isBlocked ? 'Unblock' : 'Block',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF3E0),
                    foregroundColor: const Color(0xFFE65100),
                    minimumSize: const Size(double.infinity, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _blockUser(uid, isBlocked),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Delete', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFEBEE),
                    foregroundColor: const Color(0xFFC62828),
                    minimumSize: const Size(double.infinity, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _confirmDelete(uid, name),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00695C),
        foregroundColor: Colors.white,
        title: const Text(
          'User Management',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.notifications_none, size: 20),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _users.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to load users.\nPlease try again later.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData ||
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data!.docs;
          final List<Map<String, dynamic>> allUsers = allDocs.map((doc) {
            return {..._safeData(doc), 'uid': doc.id};
          }).toList();

          final Set<String> roles = allUsers
              .map((u) => u['role'] as String)
              .where((r) => r.isNotEmpty)
              .toSet();

          final filteredUsers = allUsers.where((user) {
            final name = (user['name'] as String).toLowerCase();
            final phone = (user['phone'] as String).toLowerCase();
            final email = (user['email'] as String).toLowerCase();
            final role = user['role'] as String;

            final matchesSearch =
                _searchText.isEmpty ||
                name.contains(_searchText) ||
                phone.contains(_searchText) ||
                email.contains(_searchText);

            final matchesRole =
                _selectedRoleFilter == null || role == _selectedRoleFilter;

            return matchesSearch && matchesRole;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _searchText = value.toLowerCase().trim()),
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, phone...',
                    hintStyle: const TextStyle(fontSize: 14),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (roles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text(
                            'All',
                            style: TextStyle(fontSize: 12),
                          ),
                          selected: _selectedRoleFilter == null,
                          onSelected: (_) =>
                              setState(() => _selectedRoleFilter = null),
                          backgroundColor: Colors.white,
                          selectedColor: const Color(
                            0xFF00695C,
                          ).withOpacity(0.2),
                          checkmarkColor: const Color(0xFF00695C),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: _selectedRoleFilter == null
                                ? const Color(0xFF00695C)
                                : Colors.black,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ...roles.map((role) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(
                                role,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: _selectedRoleFilter == role,
                              onSelected: (_) =>
                                  setState(() => _selectedRoleFilter = role),
                              backgroundColor: Colors.white,
                              selectedColor: const Color(
                                0xFF00695C,
                              ).withOpacity(0.2),
                              checkmarkColor: const Color(0xFF00695C),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                color: _selectedRoleFilter == role
                                    ? const Color(0xFF00695C)
                                    : Colors.black,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: filteredUsers.isEmpty
                    ? const Center(
                        child: Text(
                          'No users found',
                          style: TextStyle(fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          final originalDoc = allDocs.firstWhere(
                            (doc) => doc.id == user['uid'],
                          );
                          return KeyedSubtree(
                            key: ValueKey(user['uid']),
                            child: _userCard(originalDoc),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
