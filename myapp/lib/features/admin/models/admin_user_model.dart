class AdminUserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  final bool isBlocked;
  final String? profileImage;
  final DateTime? createdAt;

  AdminUserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.isBlocked,
    this.profileImage,
    this.createdAt,
  });

  /// Convert Firestore → Model
  factory AdminUserModel.fromMap(Map<String, dynamic> map, String documentId) {
    return AdminUserModel(
      uid: documentId,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'] ?? 'Sender',
      isBlocked: map['isBlocked'] ?? false,
      profileImage: map['profileImage'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : null,
    );
  }

  /// Convert Model → Firestore
  Map<String, dynamic> toMap() {
    return {
      "uid": uid,
      "name": name,
      "email": email,
      "phone": phone,
      "role": role,
      "isBlocked": isBlocked,
      "profileImage": profileImage,
      "createdAt": createdAt?.toIso8601String(),
    };
  }
}