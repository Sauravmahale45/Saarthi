// lib/features/tracking/parcel_tracking_screen.dart
// Corrected version with reliable polyline, distance/ETA, and no rebuild loops

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// ── Brand colours ──────────────────────────────────────────────────────────
const _indigo = Color(0xFF4F46E5);
const _teal = Color(0xFF14B8A6);
const _orange = Color(0xFFF97316);
const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);
const _bg = Color(0xFFF5F7FF);
const _text1 = Color(0xFF0F172A);
const _text2 = Color(0xFF64748B);

class ParcelTrackingScreen extends StatefulWidget {
  final String parcelId;
  final double destLat;
  final double destLng;
  final String destLabel;
  final String travelerName;

  const ParcelTrackingScreen({
    super.key,
    required this.parcelId,
    required this.destLat,
    required this.destLng,
    required this.destLabel,
    required this.travelerName,
  });

  @override
  State<ParcelTrackingScreen> createState() => _ParcelTrackingScreenState();
}

class _ParcelTrackingScreenState extends State<ParcelTrackingScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  // Firestore subscription (replaces StreamBuilder)
  StreamSubscription<DocumentSnapshot>? _locationSubscription;

  // State variables
  LatLng? _travelerPos;
  double? _travelerHeading;
  List<LatLng> _routePoints = [];
  double _distanceKm = 0;
  double _speedKmh = 0;
  int _etaMinutes = 0;
  bool _fetchingRoute = false;
  bool _routeError = false;
  String _statusText = 'Locating traveler…';

  // For change detection – store last processed position
  LatLng? _lastProcessedPos;

  Timer? _routeDebounce;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  late final LatLng _dest = LatLng(widget.destLat, widget.destLng);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.85,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Set up Firestore listener
    _locationSubscription = FirebaseFirestore.instance
        .collection('locations')
        .doc(widget.parcelId)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists && snapshot.data() != null) {
              _onLocationUpdate(snapshot.data()! as Map<String, dynamic>);
            }
          },
          onError: (error) {
            debugPrint('Location stream error: $error');
          },
        );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _routeDebounce?.cancel();
    _locationSubscription?.cancel(); // Clean up subscription
    super.dispose();
  }

  /// Called whenever a new location document arrives.
  /// Only proceeds if the coordinates have actually changed.
  void _onLocationUpdate(Map<String, dynamic> data) {
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    final speed = (data['speed'] as num?)?.toDouble() ?? 0;
    final heading = (data['heading'] as num?)?.toDouble();

    if (lat == null || lng == null) return;

    final newPos = LatLng(lat, lng);

    // Ignore if coordinates are essentially the same (epsilon ~11m)
    if (_lastProcessedPos != null) {
      const epsilon = 0.0001;
      if ((newPos.latitude - _lastProcessedPos!.latitude).abs() < epsilon &&
          (newPos.longitude - _lastProcessedPos!.longitude).abs() < epsilon) {
        return;
      }
    }

    // Update state with new data
    setState(() {
      _travelerPos = newPos;
      _travelerHeading = heading;
      _speedKmh = speed * 3.6;
      _statusText = 'Parcel is on the way';
      _lastProcessedPos = newPos;
    });

    // Move map camera to new position (using move, not animate)
    _mapController.move(newPos, _mapController.camera.zoom);

    // Debounce route fetch: wait 1.5s after last movement
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 1500), () {
      _fetchRoute(newPos);
    });
  }

  Future<void> _fetchRoute(LatLng from) async {
    if (_fetchingRoute) return;

    setState(() {
      _fetchingRoute = true;
      _routeError = false;
    });

    try {
      // OSRM public server
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${_dest.longitude},${_dest.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('OSRM status ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>;

      if (routes.isEmpty) {
        throw Exception('No routes found');
      }

      final route = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List<dynamic>;

      final points = coords
          .map((c) => LatLng((c as List)[1] as double, (c)[0] as double))
          .toList();

      final distanceM = (route['distance'] as num?)?.toDouble() ?? 0;
      final durationS = (route['duration'] as num?)?.toDouble() ?? 0;

      setState(() {
        _routePoints = points;
        _distanceKm = distanceM / 1000;
        _etaMinutes = (durationS / 60).ceil();
        _fetchingRoute = false;
      });
    } catch (e) {
      debugPrint('Route fetch failed: $e – using straight line fallback');
      // Fallback: straight line between traveler and destination
      setState(() {
        _routePoints = [from, _dest]; // ensures at least two points
        _routeError = true;
        _fetchingRoute = false;
        _distanceKm = _haversineKm(from, _dest);
        // Assume average speed 30 km/h for ETA estimate
        _etaMinutes = (_distanceKm / 30 * 60).ceil();
      });
    }
  }

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

  @override
  Widget build(BuildContext context) {
    // No StreamBuilder – just use current state
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(context),
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: Center(child: _buildStatusChip()),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomCard()),
          if (_fetchingRoute && _travelerPos != null)
            Positioned(top: 150, right: 20, child: _buildRouteLoadingPill()),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final initialCenter = _travelerPos ?? _dest;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 14.0,
        minZoom: 4,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        // CartoDB Voyager tiles (free, clean)
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.saarthi.app',
          maxZoom: 18,
        ),

        // Route polyline
        if (_routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: _indigo,
                strokeWidth: 5,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
            ],
          ),

        // Markers
        MarkerLayer(
          markers: [
            Marker(
              point: _dest,
              width: 50,
              height: 60,
              child: _DestinationMarker(label: widget.destLabel),
            ),
            if (_travelerPos != null)
              Marker(
                point: _travelerPos!,
                width: 70,
                height: 70,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => _TravelerMarker(
                    scale: _pulse.value,
                    name: widget.travelerName,
                    speedKmh: _speedKmh,
                    heading: _travelerHeading,
                  ),
                ),
              ),
          ],
        ),

        // Attribution (required for tile license)
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
          ],
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: _text1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live Tracking',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _text1,
                    ),
                  ),
                  Text(
                    'Parcel ${widget.parcelId.substring(0, 8)}…',
                    style: const TextStyle(fontSize: 11, color: _text2),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                if (_travelerPos != null) {
                  _mapController.move(
                    _travelerPos!,
                    _mapController.camera.zoom,
                  );
                }
              },
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _indigo,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.my_location_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    final color = _travelerPos == null ? _orange : _green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            _statusText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Traveler info row
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _indigo.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.travelerName.isNotEmpty
                        ? widget.travelerName[0].toUpperCase()
                        : 'T',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _indigo,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.travelerName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _text1,
                      ),
                    ),
                    const Text(
                      'Your delivery partner',
                      style: TextStyle(fontSize: 12, color: _text2),
                    ),
                  ],
                ),
              ),
              if (_travelerPos != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _teal.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed_rounded, size: 13, color: _teal),
                      const SizedBox(width: 4),
                      Text(
                        '${_speedKmh.toStringAsFixed(0)} km/h',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _teal,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ETA + Distance + Destination row
          if (_travelerPos != null)
            Row(
              children: [
                _InfoPill(
                  icon: Icons.access_time_rounded,
                  label: 'ETA',
                  value: _etaMinutes > 0 ? '$_etaMinutes min' : 'Calculating…',
                  color: _indigo,
                ),
                const SizedBox(width: 10),
                _InfoPill(
                  icon: Icons.route_rounded,
                  label: 'Distance',
                  value: _distanceKm > 0
                      ? '${_distanceKm.toStringAsFixed(1)} km'
                      : '—',
                  color: _orange,
                ),
                const SizedBox(width: 10),
                _InfoPill(
                  icon: Icons.location_on_rounded,
                  label: 'Destination',
                  value: widget.destLabel,
                  color: _green,
                ),
              ],
            )
          else
            const _WaitingForTraveler(),

          if (_routeError) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _orange.withOpacity(0.25)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, size: 13, color: _orange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Using straight‑line estimate (road data unavailable)',
                      style: TextStyle(fontSize: 11, color: _orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteLoadingPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(color: _indigo, strokeWidth: 2),
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
}

// ════════════════════════════════════════════════════════════════════════════
//  TRAVELER MARKER (with rotation)
// ════════════════════════════════════════════════════════════════════════════
class _TravelerMarker extends StatelessWidget {
  final double scale;
  final String name;
  final double speedKmh;
  final double? heading;

  const _TravelerMarker({
    required this.scale,
    required this.name,
    required this.speedKmh,
    this.heading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: scale,
          child: Transform.rotate(
            angle: heading == null ? 0 : (heading! * math.pi / 180),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _indigo,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: _indigo.withOpacity(0.45),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.delivery_dining_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: _indigo,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            name.split(' ').first,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _green,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: _green.withOpacity(0.4),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.flag_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _green,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label.length > 10 ? '${label.substring(0, 10)}…' : label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  INFO PILL
// ════════════════════════════════════════════════════════════════════════════
class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 9, color: _text2)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  WAITING FOR TRAVELER
// ════════════════════════════════════════════════════════════════════════════
class _WaitingForTraveler extends StatelessWidget {
  const _WaitingForTraveler();

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
              style: TextStyle(fontSize: 12, color: _orange, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
