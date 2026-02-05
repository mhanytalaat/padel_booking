import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_header.dart';
import 'dart:async';
import 'court_booking_screen.dart';

class LocationsMapScreen extends StatefulWidget {
  const LocationsMapScreen({super.key});

  @override
  State<LocationsMapScreen> createState() => _LocationsMapScreenState();
}

class _LocationsMapScreenState extends State<LocationsMapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};
  bool _isLoading = true;
  
  // Default center (Cairo, Egypt)
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(30.0444, 31.2357),
    zoom: 11,
  );

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      debugPrint('Loading locations...');
      final snapshot = await FirebaseFirestore.instance
          .collection('courtLocations')
          .get();

      debugPrint('Found ${snapshot.docs.length} locations');

      final markers = <Marker>{};
      LatLngBounds? bounds;
      List<LatLng> positions = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final latitude = (data['lat'] as num?)?.toDouble();
        final longitude = (data['lng'] as num?)?.toDouble();
        final name = data['name'] as String? ?? 'Unknown';
        final address = data['address'] as String? ?? '';

        debugPrint('Location: $name - Lat: $latitude, Lng: $longitude');

        if (latitude != null && longitude != null) {
          final position = LatLng(latitude, longitude);
          positions.add(position);

          markers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: position,
              infoWindow: InfoWindow(
                title: name,
                snippet: address,
                onTap: () {
                  // Navigate to booking screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CourtBookingScreen(locationId: doc.id),
                    ),
                  );
                },
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            ),
          );
        }
      }

      debugPrint('Created ${markers.length} markers');

      // Calculate bounds if we have locations
      if (positions.isNotEmpty) {
        double minLat = positions.first.latitude;
        double maxLat = positions.first.latitude;
        double minLng = positions.first.longitude;
        double maxLng = positions.first.longitude;

        for (var pos in positions) {
          if (pos.latitude < minLat) minLat = pos.latitude;
          if (pos.latitude > maxLat) maxLat = pos.latitude;
          if (pos.longitude < minLng) minLng = pos.longitude;
          if (pos.longitude > maxLng) maxLng = pos.longitude;
        }

        bounds = LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        );
      }

      if (mounted) {
        setState(() {
          _markers.addAll(markers);
          _isLoading = false;
        });
        
        debugPrint('Map loaded with ${markers.length} markers. isLoading: $_isLoading, markers: ${_markers.length}');

        // Adjust camera to show all markers
        if (bounds != null) {
          final controller = await _controller.future;
          controller.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 100),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading locations: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading locations: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: const AppHeader(
        title: 'Locations Map',
        showNotifications: false,
        showAdminButton: false,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _markers.isEmpty
              ? Container(
                  color: const Color(0xFF0A0E27),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.location_off,
                            size: 80,
                            color: Colors.white54,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'No locations with coordinates found',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Ask admin to add latitude/longitude for each location in Admin Panel > Manage Court Locations > Edit Location',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Back to Locations'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : GoogleMap(
                  initialCameraPosition: _initialPosition,
                  markers: _markers,
                  onMapCreated: (GoogleMapController controller) {
                    _controller.complete(controller);
                  },
                  myLocationButtonEnabled: true,
                  myLocationEnabled: true,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: true,
                ),
    );
  }
}
