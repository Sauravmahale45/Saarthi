import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRAVELER KYC DETAILS SCREEN
//
// Reads from the flat Firestore schema written by the traveler KYC form:
//   users/{uid}/
//     fullName      : String   ← from KYC form "Full Name" field
//     email         : String
//     dateOfBirth   : String   ← e.g. "2000-03-17"
//     address       : String   ← e.g. "lasalgaon nashik Maharashtra"
//     documentType  : String   ← e.g. "Aadhaar Card"
//     documentUrl   : String   ← government ID photo (Cloudinary / Storage URL)
//     selfieUrl     : String   ← live selfie photo
//     status        : String   ← form writes "submitted"; admin writes "approved"/"rejected"
//     kycStatus     : String   ← admin-side alias (fallback)
//     kycVerified   : bool
//     submittedAt   : Timestamp
//     kycReviewedAt : Timestamp
// ─────────────────────────────────────────────────────────────────────────────

class TravelerKycDetailsScreen extends StatefulWidget {
  const TravelerKycDetailsScreen({
    super.key,
    required this.travelerId,
    required this.travelerData,
  });

  final String travelerId;

  /// Flat Firestore document map passed from TravelerManagementScreen.
  final Map<String, dynamic> travelerData;

  @override
  State<TravelerKycDetailsScreen> createState() =>
      _TravelerKycDetailsScreenState();
}

class _TravelerKycDetailsScreenState
    extends State<TravelerKycDetailsScreen> {
  bool _isUpdating = false;

  // ── Firestore update ─────────────────────────────────────────────────────

  Future<void> _updateKycStatus({
    required bool verified,
    required String status,
  }) async {
    setState(() => _isUpdating = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.travelerId)
          .update({
        'kycVerified'  : verified,
        'kycStatus'    : status,
        'kycReviewedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _showToast(
        verified ? 'KYC Approved successfully' : 'KYC Rejected',
        verified ? _kSuccess : _kDanger,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showToast('Update failed: $e', _kDanger);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ── Dialogs & toasts ─────────────────────────────────────────────────────

  void _showToast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }

  // ── Safe field helpers ───────────────────────────────────────────────────

  /// Read a top-level String field safely.
  String _str(String key, {String fallback = ''}) {
    final v = widget.travelerData[key];
    return (v is String && v.trim().isNotEmpty) ? v.trim() : fallback;
  }

  /// Read a URL string; returns null when missing / empty.
  String? _url(String key) {
    final v = widget.travelerData[key];
    return (v is String && v.trim().isNotEmpty) ? v.trim() : null;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ── Read flat Firestore fields written by the traveler KYC form ────────
    // fullName is what the form writes; fall back to "name" for older docs
    final String  name        = _str('fullName',     fallback: _str('name', fallback: 'Unknown'));
    final String  email       = _str('email');
    final String  dateOfBirth = _str('dateOfBirth');   // e.g. "2000-03-17"
    final String  address     = _str('address');       // e.g. "lasalgaon nashik Maharashtra"
    final String  docType     = _str('documentType');  // e.g. "Aadhaar Card"
    final String? photo       = _url('photoUrl');

    // Document photos uploaded by the traveler
    final String? docUrl      = _url('documentUrl');   // government ID photo
    final String? selfieUrl   = _url('selfieUrl');     // live selfie photo

    // Form writes "status"; admin panel writes "kycStatus" — accept both
    final String rawStatus = _str('status', fallback: _str('kycStatus', fallback: 'not_submitted'));
    // Normalise: "requested" == "submitted" (some form versions use "requested")
    final String kycStatus = (rawStatus == 'requested') ? 'submitted' : rawStatus;
    final bool   verified  = widget.travelerData['kycVerified'] == true
                          || rawStatus == 'approved';

    final Timestamp? submittedAt = widget.travelerData['submittedAt']   as Timestamp?;
    final Timestamp? reviewedAt  = widget.travelerData['kycReviewedAt'] as Timestamp?;

    if (kDebugMode) {
      debugPrint(
        'KycDetails [${widget.travelerId}]  '
        'docUrl=\$docUrl  selfieUrl=\$selfieUrl  '
        'rawStatus=\$rawStatus  kycStatus=\$kycStatus  verified=\$verified',
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1D23),
        elevation:        0,
        surfaceTintColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('KYC Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            Text('ID: ${widget.travelerId}',
                style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status banner ─────────────────────────────────────────────
            _StatusBanner(verified: verified, kycStatus: kycStatus),

            const SizedBox(height: 20),

            // ── Traveler information ──────────────────────────────────────
            _SectionCard(
              title: 'Traveler Information',
              icon:  Icons.person_outline,
              child: _ProfileSection(
                name:        name,
                email:       email,
                dateOfBirth: dateOfBirth,
                address:     address,
                documentType: docType,
                photo:       photo,
              ),
            ),

            const SizedBox(height: 16),

            // ── KYC timeline ─────────────────────────────────────────────
            if (submittedAt != null || reviewedAt != null) ...[
              _SectionCard(
                title: 'KYC Timeline',
                icon:  Icons.timeline,
                child: _TimelineSection(
                  submittedAt: submittedAt,
                  reviewedAt:  reviewedAt,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── KYC documents ─────────────────────────────────────────────
            _SectionCard(
              title: 'KYC Documents',
              icon:  Icons.photo_library_outlined,
              child: _KycDocumentsSection(
                docUrl:    docUrl,
                selfieUrl: selfieUrl,
              ),
            ),

            const SizedBox(height: 28),

            // ── Admin action buttons (only when pending) ──────────────────
            if (kycStatus == 'submitted')
              _isUpdating
                  ? const Center(child: CircularProgressIndicator())
                  : _ActionButtons(
                      onApprove: () => _confirmAction(
                        title:        'Approve KYC?',
                        message:      "This will verify the traveler's identity "
                                      'and allow them to use the platform.',
                        confirmLabel: 'Approve',
                        confirmColor: _kSuccess,
                        onConfirm:    () => _updateKycStatus(
                            verified: true, status: 'approved'),
                      ),
                      onReject: () => _confirmAction(
                        title:        'Reject KYC?',
                        message:      'The traveler will need to resubmit documents.',
                        confirmLabel: 'Reject',
                        confirmColor: _kDanger,
                        onConfirm:    () => _updateKycStatus(
                            verified: false, status: 'rejected'),
                      ),
                    ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KYC DOCUMENTS SECTION
// documentUrl  → Government ID photo
// selfieUrl    → Live selfie
// ─────────────────────────────────────────────────────────────────────────────

class _KycDocumentsSection extends StatelessWidget {
  const _KycDocumentsSection({
    required this.docUrl,      // documentUrl from Firestore
    required this.selfieUrl,   // selfieUrl from Firestore
  });

  final String? docUrl;
  final String? selfieUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DocPhotoTile(
          label:       'Government ID Photo',
          subtitle:    'Official identity document',
          icon:        Icons.credit_card_outlined,
          accentColor: _kPrimary,
          imageUrl:    docUrl,
        ),
        const SizedBox(height: 16),
        _DocPhotoTile(
          label:       'Live Selfie Verification',
          subtitle:    'Taken at time of KYC submission',
          icon:        Icons.face_outlined,
          accentColor: const Color(0xFF7B3FE4),
          imageUrl:    selfieUrl,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCUMENT PHOTO TILE
// ─────────────────────────────────────────────────────────────────────────────

class _DocPhotoTile extends StatelessWidget {
  const _DocPhotoTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.imageUrl,
  });

  final String  label;
  final String  subtitle;
  final IconData icon;
  final Color   accentColor;
  final String? imageUrl;

  void _openFullScreen(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullImageViewer(imageUrl: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label row
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color:        accentColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: accentColor),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize:   13,
                      color:      Color(0xFF1A1D23))),
              Text(subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ]),

        const SizedBox(height: 10),

        // Photo card
        GestureDetector(
          onTap: imageUrl != null
              ? () => _openFullScreen(context, imageUrl!)
              : null,
          child: Container(
            height:      190,
            width:       double.infinity,
            decoration:  BoxDecoration(
              color:        const Color(0xFFF4F6FB),
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: const Color(0xFFE0E4F0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageUrl != null
                ? _NetworkPhoto(url: imageUrl!)
                : _MissingPlaceholder(label: label),
          ),
        ),
      ],
    );
  }
}

// ── Network image with loading / error states ─────────────────────────────────

class _NetworkPhoto extends StatelessWidget {
  const _NetworkPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit:            BoxFit.cover,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : const Center(child: CircularProgressIndicator()),
          errorBuilder:   (_, __, ___) => _ErrorPlaceholder(),
        ),
        // Tap-to-zoom hint
        Positioned(
          bottom: 8, right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color:        Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.zoom_in, size: 12, color: Colors.white),
                SizedBox(width: 4),
                Text('Tap to expand',
                    style: TextStyle(fontSize: 10, color: Colors.white)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.broken_image_outlined, size: 36, color: Colors.grey[400]),
      const SizedBox(height: 6),
      Text('Failed to load image',
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    ]),
  );
}

class _MissingPlaceholder extends StatelessWidget {
  const _MissingPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.image_not_supported_outlined,
          size: 36, color: Colors.grey[400]),
      const SizedBox(height: 6),
      Text('$label not uploaded',
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FULL-SCREEN IMAGE VIEWER
// ─────────────────────────────────────────────────────────────────────────────

class _FullImageViewer extends StatelessWidget {
  const _FullImageViewer({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Document Preview'),
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: Image.network(
            imageUrl,
            loadingBuilder: (_, child, p) =>
                p == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (_, __, ___) => const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.broken_image, color: Colors.white54, size: 48),
                SizedBox(height: 8),
                Text('Failed to load image',
                    style: TextStyle(color: Colors.white54)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION BUTTONS
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.onApprove, required this.onReject});

  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kSuccess,
            foregroundColor: Colors.white,
            padding:  const EdgeInsets.symmetric(vertical: 14),
            shape:    RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          onPressed: onApprove,
          icon:  const Icon(Icons.check_circle_outline),
          label: const Text('Approve KYC',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kDanger,
            foregroundColor: Colors.white,
            padding:  const EdgeInsets.symmetric(vertical: 14),
            shape:    RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          onPressed: onReject,
          icon:  const Icon(Icons.cancel_outlined),
          label: const Text('Reject KYC',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.verified, required this.kycStatus});

  final bool   verified;
  final String kycStatus;

  @override
  Widget build(BuildContext context) {
    late Color   bg, border, textColor;
    late IconData icon;
    late String  label, sublabel;

    if (verified) {
      bg = const Color(0xFFE8F5E9); border = const Color(0xFFA5D6A7);
      textColor = _kSuccess; icon = Icons.verified_user;
      label = 'KYC Verified';
      sublabel = 'Identity has been successfully verified.';
    } else if (kycStatus == 'submitted') {
      bg = const Color(0xFFFFF8F0); border = const Color(0xFFFFCC80);
      textColor = const Color(0xFFE67E22); icon = Icons.pending_actions;
      label = 'Awaiting Review';
      sublabel = 'Documents submitted and pending admin review.';
    } else if (kycStatus == 'rejected') {
      bg = const Color(0xFFFFEBEE); border = const Color(0xFFEF9A9A);
      textColor = _kDanger; icon = Icons.cancel;
      label = 'KYC Rejected';
      sublabel = 'Traveler must resubmit documents.';
    } else {
      bg = const Color(0xFFF5F5F5); border = const Color(0xFFE0E0E0);
      textColor = Colors.grey; icon = Icons.help_outline;
      label = 'Not Submitted';
      sublabel = 'No KYC documents have been submitted yet.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        bg,
        border:       Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, color: textColor, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
            const SizedBox(height: 2),
            Text(sublabel,
                style: TextStyle(fontSize: 12, color: textColor)),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION CARD
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String   title;
  final IconData icon;
  final Widget   child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: const Color(0xFFE8ECF4)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 16, color: _kPrimary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize:   13,
                      color:      Color(0xFF1A1D23))),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFF0F2F8)),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.name,
    required this.email,
    required this.dateOfBirth,
    required this.address,
    required this.documentType,
    required this.photo,
  });

  final String  name, email, dateOfBirth, address, documentType;
  final String? photo;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius:          32,
          backgroundColor: const Color(0xFFE8ECF4),
          backgroundImage: photo != null ? NetworkImage(photo!) : null,
          child: photo == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontSize:   24,
                      fontWeight: FontWeight.bold,
                      color:      _kPrimary),
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              _DetailRow(label: 'Email',        value: email,        icon: Icons.email_outlined),
              _DetailRow(label: 'Date of Birth', value: dateOfBirth, icon: Icons.cake_outlined),
              _DetailRow(label: 'Address',       value: address,     icon: Icons.location_on_outlined),
              _DetailRow(label: 'Document',      value: documentType, icon: Icons.credit_card_outlined),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String   label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Text('$label: ',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIMELINE SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineSection extends StatelessWidget {
  const _TimelineSection(
      {required this.submittedAt, required this.reviewedAt});

  final Timestamp? submittedAt;
  final Timestamp? reviewedAt;

  static String _fmt(Timestamp ts) {
    final dt = ts.toDate().toLocal();
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (submittedAt != null)
        _TimelineRow(
          icon:  Icons.upload_file,
          color: _kPrimary,
          label: 'Documents Submitted',
          date:  _fmt(submittedAt!),
        ),
      if (reviewedAt != null)
        _TimelineRow(
          icon:  Icons.rate_review_outlined,
          color: _kSuccess,
          label: 'Admin Reviewed',
          date:  _fmt(reviewedAt!),
        ),
    ]);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.date,
  });

  final IconData icon;
  final Color    color;
  final String   label, date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        CircleAvatar(
          radius:          14,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          Text(date,
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COLORS
// ─────────────────────────────────────────────────────────────────────────────

const Color _kPrimary = Color(0xFF3B5BDB);
const Color _kSuccess = Color(0xFF2E7D32);
const Color _kDanger  = Color(0xFFC62828);