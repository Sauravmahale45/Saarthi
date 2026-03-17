import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// ── Brand / UI colours ─────────────────────────────────────────────────────
const _blue = Color(0xFF2D7DF6); // Uber-style route blue
const _green = Color(0xFF22C55E); // destination marker
const _orange = Color(0xFFF97316); // warnings / fallback
const _bg = Color(0xFFF0F4FF);
const _surface = Colors.white;
const _text1 = Color(0xFF0F172A);
const _text2 = Color(0xFF64748B);
const _text3 = Color(0xFF94A3B8);

// ── Route polyline constants ────────────────────────────────────────────────
const _routeShadowColor = Color(0x26000000); // black 15%
const _routeBorderColor = Colors.white;
const _routeMainColor = _blue;

// ════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════════════════════
class ParcelTrackingScreen extends StatefulWidget {
  final String parcelId;

  // Optional: pass these directly to skip the parcels/{id} Firestore fetch.
  final double? destLat;
  final double? destLng;
  final String? destLabel;
  final String? travelerName;

  const ParcelTrackingScreen({
    super.key,
    required this.parcelId,
    this.destLat,
    this.destLng,
    this.destLabel,
    this.travelerName,
  });

  @override
  State<ParcelTrackingScreen> createState() => _ParcelTrackingScreenState();
}

class _ParcelTrackingScreenState extends State<ParcelTrackingScreen>
    with TickerProviderStateMixin {
  final List<double> _speedHistory = [];
  double _avgSpeed = 0;
  // ── Controllers ────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();

  // Marker animation (lerp between GPS positions)
  late AnimationController _moveCtrl;
  late Animation<double> _moveTween;

  // Pulse animation for the traveler dot
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  // ── Firestore subscriptions ────────────────────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _locationSub;
  StreamSubscription<DocumentSnapshot>? _parcelSub;

  // ── Route / position state ─────────────────────────────────────────────────
  LatLng? _travelerPos; // animated current position
  LatLng? _prevPos; // position at start of lerp
  LatLng? _targetPos; // position at end of lerp
  double? _heading;
  double _speedKmh = 0;

  LatLng? _dest;
  String _destLabel = '';
  String _travelerName = '';

  List<LatLng> _routePoints = [];
  double _distanceKm = 0;
  int _etaMinutes = 0;

  bool _fetchingRoute = false;
  bool _routeError = false;
  bool _cameraFitDone = false; // fit-to-bounds only on first route load

  String _statusText = 'Locating traveler…';

  Timer? _routeDebounce;

  // ── Last processed position (for epsilon dedup) ────────────────────────────
  LatLng? _lastProcessedPos;

  // ── Distance bubble visibility ─────────────────────────────────────────────
  bool _showDistanceBubble = false;

  // ════════════════════════════════════════════════════════════════════════════
  //  LIFECYCLE
  // ════════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();

    // Smooth marker movement animation (600 ms)
    _moveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _moveTween = CurvedAnimation(parent: _moveCtrl, curve: Curves.easeInOut);
    _moveCtrl.addListener(_onMoveAnimTick);

    // Pulse animation for glowing ring around traveler
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.82,
      end: 1.18,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Seed from widget props (skip Firestore parcel fetch if already provided)
    if (widget.destLat != null && widget.destLng != null) {
      _dest = LatLng(widget.destLat!, widget.destLng!);
      _destLabel = widget.destLabel ?? '';
      _travelerName = widget.travelerName ?? 'Traveler';
    } else {
      _subscribeToParcel();
    }

    _subscribeToLocation();
  }

  @override
  void dispose() {
    _moveCtrl.removeListener(_onMoveAnimTick);
    _moveCtrl.dispose();
    _pulseCtrl.dispose();
    _routeDebounce?.cancel();
    _locationSub?.cancel();
    _parcelSub?.cancel();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  FIRESTORE SUBSCRIPTIONS
  // ════════════════════════════════════════════════════════════════════════════

  void _subscribeToParcel() {
    _parcelSub = FirebaseFirestore.instance
        .collection('parcels')
        .doc(widget.parcelId)
        .snapshots()
        .listen(
          (snap) {
            if (!snap.exists || snap.data() == null) return;
            final d = snap.data()!;
            final drop = d['drop'] as Map<String, dynamic>?;
            if (drop == null) return;

            final lat = (drop['lat'] as num?)?.toDouble();
            final lng = (drop['lng'] as num?)?.toDouble();
            final address = (drop['address'] as String?) ?? '';

            if (lat != null && lng != null && mounted) {
              setState(() {
                _dest = LatLng(lat, lng);
                _destLabel = address;
                _travelerName = (d['travelerName'] as String?) ?? 'Traveler';
              });
            }
          },
          onError: (e) =>
              debugPrint('ParcelTrackingScreen: parcel sub error – $e'),
        );
  }

  void _subscribeToLocation() {
    _locationSub = FirebaseFirestore.instance
        .collection('locations')
        .doc(widget.parcelId)
        .snapshots()
        .listen(
          (snap) {
            if (!snap.exists || snap.data() == null) return;
            _onLocationUpdate(snap.data()! as Map<String, dynamic>);
          },
          onError: (e) =>
              debugPrint('ParcelTrackingScreen: location sub error – $e'),
        );
  }

  int _calculateEtaMinutes(double distanceKm, double avgSpeed) {
    if (distanceKm <= 0) return 0;

    if (avgSpeed < 5) {
      avgSpeed = 20; // fallback speed
    }

    final hours = distanceKm / avgSpeed;

    return (hours * 60).ceil();
  }
  // ════════════════════════════════════════════════════════════════════════════
  //  LOCATION UPDATE HANDLER
  // ════════════════════════════════════════════════════════════════════════════

  // void _onLocationUpdate(Map<String, dynamic> data) {
  //   final lat = (data['latitude'] as num?)?.toDouble();
  //   final lng = (data['longitude'] as num?)?.toDouble();
  //   final speed = (data['speed'] as num?)?.toDouble() ?? 0;
  //   final heading = (data['heading'] as num?)?.toDouble();

  //   if (lat == null || lng == null) return;

  //   final newPos = LatLng(lat, lng);

  //   // Skip if coordinates are essentially unchanged (~11 m epsilon)
  //   if (_lastProcessedPos != null) {
  //     const epsilon = 0.0001;
  //     if ((newPos.latitude - _lastProcessedPos!.latitude).abs() < epsilon &&
  //         (newPos.longitude - _lastProcessedPos!.longitude).abs() < epsilon) {
  //       return;
  //     }
  //   }

  //   _lastProcessedPos = newPos;

  //   // Start interpolation animation from current rendered pos → new pos
  //   _prevPos = _travelerPos ?? newPos;
  //   _targetPos = newPos;
  //   _moveCtrl
  //     ..reset()
  //     ..forward();

  //   if (mounted) {
  //     setState(() {
  //       _heading = heading;
  //       _speedKmh = speed * 3.6;
  //       _statusText = 'Parcel is on the way';
  //     });
  //   }

  //   // Debounce route fetch: 1.5 s after last position update
  //   _routeDebounce?.cancel();
  //   _routeDebounce = Timer(const Duration(milliseconds: 1500), () {
  //     if (_dest != null) _fetchRoute(newPos, _dest!);
  //   });
  // }
  void _onLocationUpdate(Map<String, dynamic> data) {
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    final speed = (data['speed'] as num?)?.toDouble() ?? 0;
    final heading = (data['heading'] as num?)?.toDouble();

    if (lat == null || lng == null) return;

    final newPos = LatLng(lat, lng);

    // Skip if coordinates are essentially unchanged (~11 m epsilon)
    if (_lastProcessedPos != null) {
      const epsilon = 0.0001;
      if ((newPos.latitude - _lastProcessedPos!.latitude).abs() < epsilon &&
          (newPos.longitude - _lastProcessedPos!.longitude).abs() < epsilon) {
        return;
      }
    }

    _lastProcessedPos = newPos;

    // Convert speed from m/s → km/h
    final speedKmh = speed * 3.6;

    // ── Speed smoothing (last 5 values) ─────────────────────
    _speedHistory.add(speedKmh);

    if (_speedHistory.length > 5) {
      _speedHistory.removeAt(0);
    }

    final avgSpeed =
        _speedHistory.reduce((a, b) => a + b) / _speedHistory.length;

    // Start interpolation animation from current rendered pos → new pos
    _prevPos = _travelerPos ?? newPos;
    _targetPos = newPos;
    _moveCtrl
      ..reset()
      ..forward();

    if (mounted) {
      setState(() {
        _heading = heading;
        _speedKmh = speedKmh;
        _statusText = 'Parcel is on the way';

        // Update ETA using average speed
        if (_distanceKm > 0) {
          _etaMinutes = _calculateEtaMinutes(_distanceKm, avgSpeed);
        }
      });
    }

    // Debounce route fetch: 1.5 s after last position update
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (_dest != null) _fetchRoute(newPos, _dest!);
    });
  }

  // Lerp tick: rebuild map with interpolated marker position
  void _onMoveAnimTick() {
    if (_prevPos == null || _targetPos == null) return;
    final t = _moveTween.value;
    final lerped = LatLng(
      _prevPos!.latitude + (_targetPos!.latitude - _prevPos!.latitude) * t,
      _prevPos!.longitude + (_targetPos!.longitude - _prevPos!.longitude) * t,
    );
    if (mounted) {
      setState(() => _travelerPos = lerped);
    }
    // Follow the traveler smoothly with the camera
    if (_cameraFitDone) {
      _mapController.move(lerped, _mapController.camera.zoom);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  ROUTE FETCH (OSRM)
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    if (_fetchingRoute) return;
    if (mounted)
      setState(() {
        _fetchingRoute = true;
        _routeError = false;
      });

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception('OSRM status ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>;
      if (routes.isEmpty) throw Exception('No routes returned');

      final route = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List<dynamic>;

      final points = coords
          .map((c) => LatLng((c as List)[1] as double, c[0] as double))
          .toList();

      final distanceM = (route['distance'] as num).toDouble();
      final durationS = (route['duration'] as num).toDouble();

      if (mounted) {
        setState(() {
          _routePoints = points;
          _distanceKm = distanceM / 1000;
          _etaMinutes = (durationS / 60).ceil();
          _fetchingRoute = false;
          _showDistanceBubble = true;
        });

        // Fit camera to full route on first successful load
        if (!_cameraFitDone && points.length >= 2) {
          _fitCameraToRoute(points);
          _cameraFitDone = true;
        }
      }
    } catch (e) {
      debugPrint(
        'ParcelTrackingScreen: route fetch failed – $e (straight-line fallback)',
      );
      if (mounted) {
        setState(() {
          _routePoints = [from, to];
          _routeError = true;
          _fetchingRoute = false;
          _distanceKm = _haversineKm(from, to);
          _etaMinutes = (_distanceKm / 30 * 60).ceil();
          _showDistanceBubble = true;
        });
        if (!_cameraFitDone) {
          _fitCameraToRoute([from, to]);
          _cameraFitDone = true;
        }
      }
    }
  }

  void _fitCameraToRoute(List<LatLng> points) {
    if (points.isEmpty) return;
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));

    // Delay one frame so the map is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.fromLTRB(48, 140, 48, 280),
          ),
        );
      } catch (_) {}
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(a.latitude)) *
            math.cos(_deg2rad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _deg2rad(double deg) => deg * math.pi / 180;

  String get _shortParcelId {
    final id = widget.parcelId;
    return id.length > 8
        ? '${id.substring(0, 8).toUpperCase()}…'
        : id.toUpperCase();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(context),
          if (_showDistanceBubble)
            Positioned(
              top: MediaQuery.of(context).padding.top + 74,
              left: 0,
              right: 0,
              child: Center(child: _buildDistanceBubble()),
            ),
          if (_fetchingRoute && _travelerPos != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 74,
              right: 16,
              child: _buildRouteLoadingPill(),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomInfoCard(),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  MAP
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildMap() {
    final initialCenter =
        _travelerPos ?? _dest ?? const LatLng(20.5937, 78.9629);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 14.0,
        minZoom: 4,
        maxZoom: 19,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        // CartoDB Voyager tiles
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.saarthi.app',
          maxZoom: 19,
          retinaMode: RetinaMode.isHighDensity(context),
        ),

        // Route polylines (shadow → border → main)
        _buildRouteLayer(),

        // Markers
        _buildMarkers(),

        // OSM attribution (required by tile license)
        RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
            TextSourceAttribution('© CARTO', onTap: () {}),
          ],
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  ROUTE LAYER  (three-pass: shadow → border → main colour)
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildRouteLayer() {
    if (_routePoints.length < 2) return const SizedBox.shrink();

    return PolylineLayer(
      polylines: [
        // 1. Shadow
        Polyline(
          points: _routePoints,
          color: _routeShadowColor,
          strokeWidth: 10,
        ),
        // 2. White border
        Polyline(
          points: _routePoints,
          color: _routeBorderColor,
          strokeWidth: 7,
        ),
        // 3. Main route
        Polyline(points: _routePoints, color: _routeMainColor, strokeWidth: 4),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  MARKERS
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildMarkers() {
    final markers = <Marker>[];

    // Destination marker
    if (_dest != null) {
      markers.add(
        Marker(
          point: _dest!,
          width: 56,
          height: 70,
          child: _DestinationMarker(
            label: _destLabel.isEmpty ? 'Drop' : _destLabel,
          ),
        ),
      );
    }

    // Traveler marker with animation
    if (_travelerPos != null) {
      markers.add(
        Marker(
          point: _travelerPos!,
          width: 80,
          height: 95,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => _TravelerMarker(
              pulseScale: _pulse.value,
              heading: _heading,
              name: _travelerName,
            ),
          ),
        ),
      );
    }

    return MarkerLayer(markers: markers);
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  TOP BAR
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          bottom: 12,
        ),
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Back button
            _TopBarButton(
              onTap: () => Navigator.pop(context),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: _text1,
              ),
            ),
            const SizedBox(width: 12),

            // Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Live Tracking',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _text1,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Order $_shortParcelId',
                    style: const TextStyle(fontSize: 11, color: _text3),
                  ),
                ],
              ),
            ),

            // Re-centre button
            _TopBarButton(
              color: _blue,
              onTap: () {
                final pos = _travelerPos;
                if (pos != null) {
                  _mapController.move(pos, _mapController.camera.zoom);
                }
              },
              child: const Icon(
                Icons.my_location_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  FLOATING DISTANCE BUBBLE
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildDistanceBubble() {
    final distStr = _distanceKm > 0
        ? '${_distanceKm.toStringAsFixed(1)} km'
        : '—';
    final etaStr = _etaMinutes > 0 ? '$_etaMinutes min away' : 'Calculating…';

    return AnimatedOpacity(
      opacity: _showDistanceBubble ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: _text1,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: _text1.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_rounded, size: 14, color: Colors.white70),
            const SizedBox(width: 7),
            Text(
              '$distStr  •  $etaStr',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.1,
              ),
            ),
            if (_routeError) ...[
              const SizedBox(width: 6),
              const Icon(Icons.warning_amber_rounded, size: 13, color: _orange),
            ],
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  ROUTE LOADING PILL
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildRouteLoadingPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(color: _blue, strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Updating route…',
            style: TextStyle(fontSize: 11, color: _text2),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  BOTTOM INFO CARD
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildBottomInfoCard() {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 18),

              // Traveler row
              _buildTravelerRow(),
              const SizedBox(height: 16),

              // Info pills or waiting state
              if (_travelerPos != null)
                _buildInfoPillRow()
              else
                const _WaitingTile(),

              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTravelerRow() {
    final initial = _travelerName.isNotEmpty
        ? _travelerName[0].toUpperCase()
        : 'T';
    return Row(
      children: [
        // Avatar
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_blue.withOpacity(0.15), _blue.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            border: Border.all(color: _blue.withOpacity(0.2), width: 1.5),
          ),
          child: Center(
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: _blue,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Name + subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _travelerName.isEmpty ? 'Your traveler' : _travelerName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _text1,
                  letterSpacing: -0.2,
                ),
              ),
              const Text(
                'Delivery partner',
                style: TextStyle(fontSize: 12, color: _text2),
              ),
            ],
          ),
        ),

        // Speed chip
        if (_travelerPos != null) _SpeedChip(speedKmh: _speedKmh),

        // Live indicator
        const SizedBox(width: 8),
        _LiveBadge(isLive: _travelerPos != null),
      ],
    );
  }

  Widget _buildInfoPillRow() {
    return Row(
      children: [
        _InfoPill(
          icon: Icons.access_time_rounded,
          value: _etaMinutes > 0 ? '$_etaMinutes min' : '…',
          label: 'ETA',
          color: _blue,
        ),
        const SizedBox(width: 10),
        _InfoPill(
          icon: Icons.route_rounded,
          value: _distanceKm > 0 ? '${_distanceKm.toStringAsFixed(1)} km' : '—',
          label: 'Distance',
          color: const Color(0xFF8B5CF6),
        ),
        const SizedBox(width: 10),
        _InfoPill(
          icon: Icons.location_on_rounded,
          value: _destLabel.isEmpty
              ? 'Drop'
              : (_destLabel.length > 12
                    ? '${_destLabel.substring(0, 12)}…'
                    : _destLabel),
          label: 'To',
          color: _green,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TRAVELER MARKER  (rotation + pulse ring)
// ════════════════════════════════════════════════════════════════════════════
class _TravelerMarker extends StatelessWidget {
  final double pulseScale;
  final double? heading;
  final String name;

  const _TravelerMarker({
    required this.pulseScale,
    required this.name,
    this.heading,
  });

  @override
  Widget build(BuildContext context) {
    final angle = heading == null ? 0.0 : heading! * math.pi / 180;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulsing outer ring
                Transform.scale(
                  scale: pulseScale,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blue.withOpacity(0.12),
                      border: Border.all(
                        color: _blue.withOpacity(0.25),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                // Icon with rotation
                Transform.rotate(
                  angle: angle,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: _blue.withOpacity(0.45),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.delivery_dining_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Name label
          if (name.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: _blue,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: _blue.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                name.split(' ').first,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  DESTINATION MARKER
// ════════════════════════════════════════════════════════════════════════════
class _DestinationMarker extends StatelessWidget {
  final String label;
  const _DestinationMarker({required this.label});

  @override
  Widget build(BuildContext context) {
    final short = label.length > 12 ? '${label.substring(0, 12)}…' : label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _green,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: _green.withOpacity(0.45),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.flag_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: _green,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: _green.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            short,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SMALL WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _TopBarButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final Color color;

  const _TopBarButton({
    required this.onTap,
    required this.child,
    this.color = const Color(0xFFF1F5F9),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: color == const Color(0xFFF1F5F9)
              ? Border.all(color: const Color(0xFFE2E8F0))
              : null,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final bool isLive;
  const _LiveBadge({required this.isLive});

  @override
  Widget build(BuildContext context) {
    final color = isLive ? _green : _orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isLive ? 'LIVE' : 'PENDING',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final double speedKmh;
  const _SpeedChip({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed_rounded, size: 12, color: _text2),
          const SizedBox(width: 4),
          Text(
            '${speedKmh.toStringAsFixed(0)} km/h',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _InfoPill({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                color: _text3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingTile extends StatelessWidget {
  const _WaitingTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _orange.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _orange.withOpacity(0.2)),
      ),
      child: Row(
        children: const [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(color: _orange, strokeWidth: 2.5),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Waiting for traveler location…\nTracking will begin shortly.',
              style: TextStyle(fontSize: 12.5, color: _orange, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
