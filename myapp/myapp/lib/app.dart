import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Screen Imports ─────────────────────────────────────────────────────────────
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_signup_screen.dart';
import 'features/auth/screens/profile_setup_screen.dart';
import 'features/auth/screens/role_selection_screen.dart';
import 'features/sender/screens/sender_home_screen.dart';
import 'features/traveler/screens/traveler_home_screen.dart';
import 'features/traveler/screens/parcel_details_traveler.dart';
import 'features/sender/screens/create_parcel_screen.dart';
import 'features/sender/screens/sender_parcels_screen.dart';
import 'features/sender/screens/available_travelers_screen.dart';
import 'features/sender/screens/parcel_details.dart';
import 'features/payment/payment_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'features/admin/screens/admin_home_screen.dart';

// ── Notification module ────────────────────────────────────────────────────────
// setRouter() gives NotificationService access to GoRouter so it can call
// router.go() / router.push() when the user taps a push-notification banner.
import 'notifications/notifications.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ROUTER PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    routes: [
      // ── Splash ────────────────────────────────────────────────────────────
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            _fadePage(key: state.pageKey, child: const SplashScreen()),
      ),

      // ── Auth ──────────────────────────────────────────────────────────────
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            _slidePage(key: state.pageKey, child: const LoginSignupScreen()),
      ),
      GoRoute(
        path: '/role',
        pageBuilder: (context, state) =>
            _slidePage(key: state.pageKey, child: const RoleSelectionScreen()),
      ),
      GoRoute(
        path: '/profile_setup',
        builder: (_, __) => const ProfileSetupScreen(),
      ),

      // ── Admin ─────────────────────────────────────────────────────────────
      GoRoute(
        path: '/admin_home',
        builder: (context, state) => const AdminHomeScreen(),
      ),

      // ── Sender ────────────────────────────────────────────────────────────
      GoRoute(
        path: '/sender',
        pageBuilder: (context, state) =>
            _fadePage(key: state.pageKey, child: const SenderHomeScreen()),
      ),
      GoRoute(
        path: '/create-parcel',
        builder: (_, __) => const CreateParcelScreen(),
      ),
      GoRoute(
        path: '/sender-parcels',
        name: 'senderParcels',
        builder: (context, state) {
          final tab = state.uri.queryParameters['tab'];
          return SenderParcelsScreen(initialTab: tab);
        },
      ),

      // Sender → available travelers for a parcel.
      // Notification type parcel_rejected navigates here so the sender
      // can immediately pick another traveler.
      GoRoute(
        path: '/available-traveler/:parcelId',
        builder: (context, state) {
          final parcelId = state.pathParameters['parcelId']!;
          return AvailableTravelersScreen(parcelId: parcelId);
        },
      ),

      // Sender → parcel detail.
      // Notification types parcel_accepted / parcel_pickup / parcel_delivered
      // all deep-link here.
      GoRoute(
        path: '/parcel-details/:parcelId',
        builder: (context, state) =>
            ParcelDetailsScreen(parcelId: state.pathParameters['parcelId']!),
      ),

      // ── Traveler ──────────────────────────────────────────────────────────
      // Notification type parcel_request navigates here (home tab shows the
      // incoming request card at the top automatically).
      GoRoute(
        path: '/traveler',
        pageBuilder: (context, state) =>
            _fadePage(key: state.pageKey, child: const TravelerHomeScreen()),
      ),

      // Traveler → parcel detail.
      // Notification type reminder navigates here.
      GoRoute(
        path: '/traveler-parcel-details/:parcelId',
        builder: (context, state) => TravelerParcelDetailsScreen(
          parcelId: state.pathParameters['parcelId']!,
        ),
      ),

      // ── Payment ───────────────────────────────────────────────────────────
      GoRoute(
        path: '/make-payment/:parcelId',
        builder: (context, state) {
          final parcelId = state.pathParameters['parcelId']!;
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('parcels')
                .doc(parcelId)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final data = snapshot.data!.data() as Map<String, dynamic>;
              return PaymentScreen(
                parcelId: parcelId,
                price: (data['price'] ?? 0).toDouble(),
                fromCity: data['fromCity'] ?? '',
                toCity: data['toCity'] ?? '',
              );
            },
          );
        },
      ),
    ],

    // ── 404 ───────────────────────────────────────────────────────────────────
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('😕', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            const Text(
              'Page not found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.error.toString(),
              style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(140, 48),
              ),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // REGISTER ROUTER WITH NOTIFICATION SERVICE
  //
  // This single line is the entire wiring between GoRouter and FCM taps.
  //
  // Why here (inside the provider body)?
  //   • routerProvider runs the first time ref.watch(routerProvider) is
  //     called, which is inside SaarthiApp.build() — AFTER ProviderScope
  //     and Firebase are ready but BEFORE any screen is painted.
  //   • At that moment the router object exists and NotificationService
  //     has already been initialised from main.dart, so its tap listeners
  //     are registered and waiting.  Storing the router here guarantees
  //     that the very first tap, even one that wakes a terminated app,
  //     will find a non-null router to navigate with.
  // ══════════════════════════════════════════════════════════════════════════
  NotificationService.setRouter(router);

  return router;
});

// ═══════════════════════════════════════════════════════════════════════════════
// APP WIDGET
// ═══════════════════════════════════════════════════════════════════════════════
class SaarthiApp extends ConsumerWidget {
  const SaarthiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Saarthi',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      routerConfig: router,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// THEME  (unchanged from original)
// ═══════════════════════════════════════════════════════════════════════════════
ThemeData _buildTheme() {
  const primary = Color(0xFFFF6B35);
  const background = Color(0xFFFAFAFA);
  const surface = Color(0xFFFFFFFF);
  const textDark = Color(0xFF1A1A1A);
  const textLight = Color(0xFF888888);
  const borderColor = Color(0xFFEEEEEE);
  const cardColor = Color(0xFFF8F8F8);
  const errorColor = Color(0xFFEF4444);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      background: background,
      surface: surface,
      primary: primary,
      onPrimary: Colors.white,
      secondary: const Color(0xFF6366F1),
      tertiary: const Color(0xFF10B981),
      error: errorColor,
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textDark,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: borderColor,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textDark,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: textDark, size: 22),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: primary.withOpacity(0.5),
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary, width: 1.5),
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardColor,
      hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
      labelStyle: const TextStyle(color: textLight, fontSize: 14),
      floatingLabelStyle: const TextStyle(
        color: primary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      prefixIconColor: textLight,
      suffixIconColor: textLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorColor, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorColor, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: borderColor, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: cardColor,
      selectedColor: primary.withOpacity(0.12),
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textDark,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1A1A1A),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
    ),
    dividerTheme: const DividerThemeData(
      color: borderColor,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: textDark,
      ),
      subtitleTextStyle: TextStyle(fontSize: 13, color: textLight),
    ),
    iconTheme: const IconThemeData(color: textDark, size: 22),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: textDark,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: textDark,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: textDark,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: textDark,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textDark,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textDark,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: textDark,
      ),
      bodyLarge: TextStyle(fontSize: 15, color: textDark),
      bodyMedium: TextStyle(fontSize: 14, color: textDark),
      bodySmall: TextStyle(fontSize: 12, color: textLight),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textDark,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: textLight,
      ),
    ),
  );
}

// ── Page Transitions (unchanged) ──────────────────────────────────────────────

CustomTransitionPage<void> _fadePage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
          child: child,
        ),
  );
}

CustomTransitionPage<void> _slidePage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}
