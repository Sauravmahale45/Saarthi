// ─────────────────────────────────────────────────────────────────────────────
//  notification_types.dart
//
//  Single source of truth for FCM `data.type` string constants.
//
//  Imported by BOTH FcmSender (writes the type into the payload) and
//  NotificationService (reads the type to decide which screen to open).
//  Keeping it in its own file breaks the circular dependency that would
//  occur if each class imported the other.
// ─────────────────────────────────────────────────────────────────────────────

class NotificationTypes {
  NotificationTypes._();

  /// Sender → Traveler: a sender has selected this traveler for a parcel.
  /// Navigation: /traveler  (home screen, incoming requests visible at top)
  static const String parcelRequest = 'parcel_request';

  /// Traveler → Sender: traveler accepted the parcel request.
  /// Navigation: /parcel-details/:parcelId
  static const String parcelAccepted = 'parcel_accepted';

  /// Traveler → Sender: traveler picked up the parcel.
  /// Navigation: /parcel-details/:parcelId
  static const String parcelPickup = 'parcel_pickup';

  /// Traveler → Sender: parcel has been delivered.
  /// Navigation: /parcel-details/:parcelId
  static const String parcelDelivered = 'parcel_delivered';

  /// Traveler → Sender: traveler rejected the request OR 15-min timer expired.
  /// Navigation: /available-traveler/:parcelId  (pick another traveler)
  static const String parcelRejected = 'parcel_rejected';

  /// Admin → Traveler: withdrawal request approved and payout processing.
  /// Navigation: /traveler  (home screen, wallet tab)
  static const String withdrawalApproved = 'withdrawal_approved';

  /// System → Traveler or Sender: generic parcel reminder.
  /// Navigation: /traveler-parcel-details/:parcelId
  static const String reminder = 'reminder';
}
