import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

const primaryColor = Color(0xFF4F46E5);
const backgroundColor = Color(0xFFF8FAFC);
const textPrimary = Color(0xFF0F172A);
const textSecondary = Color(0xFF64748B);

class SenderParcelsScreen extends StatefulWidget {
  final String? initialTab; // pending, active, delivered, or all
  const SenderParcelsScreen({super.key, this.initialTab});

  @override
  State<SenderParcelsScreen> createState() => _SenderParcelsScreenState();
}

class _SenderParcelsScreenState extends State<SenderParcelsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    int initialIndex = 0; // All
    if (widget.initialTab == 'pending') initialIndex = 1;
    if (widget.initialTab == 'active') initialIndex = 2;
    if (widget.initialTab == 'delivered') initialIndex = 3;
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _parcelsStream() {
    return FirebaseFirestore.instance
        .collection('parcels')
        .where('senderId', isEqualTo: _user?.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'My Parcels',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryColor,
          unselectedLabelColor: textSecondary,
          indicatorColor: primaryColor,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Active'),
            Tab(text: 'Delivered'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _parcelsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No parcels found'));
          }

          final allDocs = snapshot.data!.docs;
          return TabBarView(
            controller: _tabController,
            children: [
              _buildParcelList(allDocs, (doc) => true), // All
              _buildParcelList(allDocs, (doc) {
                final s = (doc.data() as Map<String, dynamic>)['status'];
                return s == 'pending' || s == 'requested';
              }),
              _buildParcelList(allDocs, (doc) {
                final s = (doc.data() as Map<String, dynamic>)['status'];
                return s == 'accepted' || s == 'picked';
              }),
              _buildParcelList(allDocs, (doc) {
                final s = (doc.data() as Map<String, dynamic>)['status'];
                return s == 'delivered';
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildParcelList(
    List<QueryDocumentSnapshot> docs,
    bool Function(QueryDocumentSnapshot) filter,
  ) {
    final filtered = docs.where(filter).toList();
    if (filtered.isEmpty) {
      return const Center(child: Text('No parcels in this category'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _ParcelCard(doc: filtered[index]),
    );
  }
}

class _ParcelCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;

  const _ParcelCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text("${data['fromCity']} → ${data['toCity']}"),
        subtitle: Text(data['description'] ?? 'Parcel'),
        trailing: Text(
          data['status'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onTap: () => context.push('/parcel-details/${doc.id}'),
      ),
    );
  }
}
