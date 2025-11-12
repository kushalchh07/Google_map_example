// Flutter Location Finder
// Single-file example (main.dart)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'constants/constants.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Location Finder',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LocationFinderPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LocationFinderPage extends StatefulWidget {
  @override
  _LocationFinderPageState createState() => _LocationFinderPageState();
}

class _LocationFinderPageState extends State<LocationFinderPage> {
  final Completer<GoogleMapController> _controller = Completer();
  StreamSubscription<Position>? _positionStream;
  Marker? _userMarker;
  LatLng _initialCameraPosition = LatLng(
    27.7172,
    85.3240,
  ); // Kathmandu fallback
  bool _mapReady = false;

  static const CameraPosition _kInitial = CameraPosition(
    target: LatLng(27.7172, 85.3240),
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStart();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // Request permission and subscribe to location updates
  Future<void> _checkPermissionsAndStart() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled - prompt the user
      await _showLocationDisabledDialog();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try asking for permissions again
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      await _showPermissionDeniedForeverDialog();
      return;
    }

    // Subscribe to location updates
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5, // meters
          ),
        ).listen((Position position) {
          _onLocationUpdate(position);
        });

    // Also fetch current position once to initialize
    Position current = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
    _onLocationUpdate(current, animate: true);
  }

  Future<void> _showLocationDisabledDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location services disabled'),
        content: const Text(
          'Please enable location services in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionDeniedForeverDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location permission'),
        content: const Text(
          'Location permission is permanently denied. Please open app settings to enable it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _onLocationUpdate(
    Position position, {
    bool animate = false,
  }) async {
    final LatLng latLng = LatLng(position.latitude, position.longitude);

    setState(() {
      _userMarker = Marker(
        markerId: const MarkerId('user_marker'),
        position: latLng,
        infoWindow: InfoWindow(
          title: 'You are here',
          snippet:
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      );
    });

    if (animate && _mapReady) {
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 17.0),
        ),
      );
    }
  }

  // Recenter map on current user location
  Future<void> _recenterMap() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final GoogleMapController controller = await _controller.future;
      final LatLng latLng = LatLng(pos.latitude, pos.longitude);
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 17.0),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to get current location')),
      );
    }
  }

  Future<void> _searchLocation(String query) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=$query&key=$apiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK') {
          final location = data['results'][0]['geometry']['location'];
          final LatLng target = LatLng(location['lat'], location['lng']);

          // Update marker and move camera
          setState(() {
            _userMarker = Marker(
              markerId: MarkerId('searched_location'),
              position: target,
              infoWindow: InfoWindow(title: query),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
            );
          });

          final GoogleMapController controller = await _controller.future;
          controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: target, zoom: 15),
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Location not found')));
        }
      } else {
        throw Exception('Failed to fetch location');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Set<Marker> markers = {};
    if (_userMarker != null) markers.add(_userMarker!);

    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            decoration: InputDecoration(
              hintText: 'Search a location...',
              border: InputBorder.none,
              hintStyle: TextStyle(color: Colors.white70),
            ),
            style: TextStyle(color: Colors.white, fontSize: 18),
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                _searchLocation(value);
              }
            },
          ),
          backgroundColor: Colors.blue,
        ),

        body: GoogleMap(
          initialCameraPosition: _kInitial,
          myLocationEnabled: false, // we manage our own marker
          myLocationButtonEnabled: false,
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
            setState(() => _mapReady = true);
          },
          markers: markers,
          mapType: MapType.normal,
          zoomControlsEnabled: false,
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'recenter',
                onPressed: _recenterMap,
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'center_to_kathmandu',
                onPressed: () async {
                  final GoogleMapController controller =
                      await _controller.future;
                  controller.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: _initialCameraPosition,
                        zoom: 14.0,
                      ),
                    ),
                  );
                },
                child: const Icon(Icons.location_city),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
