import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  final CollectionReference _users =
      FirebaseFirestore.instance.collection('users');

  // ---------------------------------------------------------------------------
  // FIRESTORE ACTIONS
  // ---------------------------------------------------------------------------

  /// Toggles the blocked state of a user document.
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

  /// Shows a confirmation dialog before permanently deleting a user.
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
  // HELPERS
  // ---------------------------------------------------------------------------

  /// Safely reads all fields from a Firestore document.
  /// Returns guaranteed non-null strings with sensible defaults so the UI
  /// never crashes when a field is absent.
  Map<String, dynamic> _safeData(QueryDocumentSnapshot doc) {
    // FIX: doc['field'] throws "Bad state: field does not exist" when the key
    // is missing.  Cast to Map and use a null-aware lookup with ?? defaults.
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
      // isBlocked can be stored as bool or missing entirely
      'isBlocked': raw['isBlocked'] == true,
    };
  }

  /// Derives the avatar initials from the display name.
  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  // ---------------------------------------------------------------------------
  // USER CARD
  // ---------------------------------------------------------------------------

  Widget _userCard(QueryDocumentSnapshot doc) {
    final String uid = doc.id;
    final Map<String, dynamic> data = _safeData(doc);

    final String name     = data['name']      as String;
    final String email    = data['email']     as String;
    final String phone    = data['phone']     as String;
    final String role     = data['role']      as String;
    final bool isBlocked  = data['isBlocked'] as bool;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            color: Color(0x14000000),
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ---- USER INFO ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE8EAF6),
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + role badge row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            // FIX: literal colors — no .shade accessor
                            color: role == 'Sender'
                                ? const Color(0xFFE3F2FD)
                                : const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: role == 'Sender'
                                  ? const Color(0xFF1565C0)
                                  : const Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        const Icon(Icons.phone, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            phone,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            email,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    Text(
                      isBlocked ? 'Blocked User' : 'Active',
                      style: TextStyle(
                        color: isBlocked ? Colors.red : Colors.green,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 20),

          // ---- ACTION BUTTONS ----
          // FIX: buttons wrapped in Expanded so Row never gets infinite-width
          // constraints (same root cause fixed in TravelerManagementScreen).
          Row(
            children: [
              // PROFILE
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.person_outline, size: 16),
                  label: const Text('Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8EAF6),
                    foregroundColor: const Color(0xFF1A237E),
                  ),
                  onPressed: () {
                    // TODO: Navigate to user profile screen
                  },
                ),
              ),

              const SizedBox(width: 8),

              // BLOCK / UNBLOCK
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.block, size: 16),
                  label: Text(isBlocked ? 'Unblock' : 'Block'),
                  style: ElevatedButton.styleFrom(
                    // FIX: literal colors — Colors.orange.shade100/800
                    // can be null and crash styleFrom
                    backgroundColor: const Color(0xFFFFE0B2), // orange.shade100
                    foregroundColor: const Color(0xFFE65100), // orange.shade800
                  ),
                  onPressed: () => _blockUser(uid, isBlocked),
                ),
              ),

              const SizedBox(width: 8),

              // DELETE
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFEBEE),
                    foregroundColor: const Color(0xFFC62828),
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
      backgroundColor: const Color(0xFFF5F6FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        title: const Text('User Management'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.notifications_none),
          ),
        ],
      ),

      body: Column(
        children: [
          // ---- SEARCH BAR ----
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchText = value.toLowerCase().trim();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // ---- LIVE USER LIST ----
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _users.snapshots(),
              builder: (context, snapshot) {
                // Error state
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to load users.\nPlease try again later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  );
                }

                // Loading state
                if (!snapshot.hasData ||
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // FIX: Filter is applied after safe data extraction so missing
                // phone/name fields never throw — they resolve to 'N/A' /
                // 'Unknown User' before the .contains() call.
                final List<QueryDocumentSnapshot> docs =
                    snapshot.data!.docs.where((doc) {
                  final Map<String, dynamic> d = _safeData(doc);
                  final String name =
                      (d['name'] as String).toLowerCase();
                  final String phone =
                      (d['phone'] as String).toLowerCase();
                  // FIX: also search by email and role for a richer filter
                  final String email =
                      (d['email'] as String).toLowerCase();

                  if (_searchText.isEmpty) return true;
                  return name.contains(_searchText) ||
                      phone.contains(_searchText) ||
                      email.contains(_searchText);
                }).toList();

                // Empty state
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No users found'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    return KeyedSubtree(
                      key: ValueKey(docs[index].id),
                      child: _userCard(docs[index]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}