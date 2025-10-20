import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/navigation_map_service.dart';

class NavigationMapPage extends StatefulWidget {
  final Map<String, dynamic> request;
  final Map<String, dynamic>? driverData;

  const NavigationMapPage({
    super.key,
    required this.request,
    this.driverData,
  });

  @override
  State<NavigationMapPage> createState() => _NavigationMapPageState();
}

class _NavigationMapPageState extends State<NavigationMapPage> {
  Position? _currentPosition;
  bool _isLoading = true;
  double? _distance;
  int? _estimatedTime;
  late WebViewController _webViewController;
  Timer? _locationUpdateTimer;
  bool _isRealTimeActive = true;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _startRealTimeUpdates();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  void _startRealTimeUpdates() {
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_isRealTimeActive && mounted) {
        _getCurrentLocation(showLoading: false);
      }
    });
  }

  Future<void> _getCurrentLocation({bool showLoading = true}) async {
    try {
      if (showLoading) {
        setState(() => _isLoading = true);
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Please enable location services');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showError('Location permission permanently denied');
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });

      // Calculate distance and estimated time
      _calculateRouteInfo(position);
      _updateWebView(position);

    } catch (e) {
      debugPrint('Error getting location: $e');
      setState(() => _isLoading = false);
      _showError('Failed to get current location');
    }
  }

  void _calculateRouteInfo(Position driverPosition) {
    final customerLoc = _customerLocation;
    if (customerLoc == null) return;

    final double? customerLat = customerLoc['latitude']?.toDouble();
    final double? customerLng = customerLoc['longitude']?.toDouble();

    if (customerLat == null || customerLng == null) return;

    // Calculate distance
    final distance = NavigationMapService.calculateDistance(
      driverPosition.latitude,
      driverPosition.longitude,
      customerLat,
      customerLng,
    );

    // Calculate estimated time
    final estimatedTime = NavigationMapService.calculateEstimatedTime(distance);

    setState(() {
      _distance = distance;
      _estimatedTime = estimatedTime;
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Map<String, dynamic>? get _customerLocation {
    final location = widget.request['location'] as Map<String, dynamic>?;
    return location?['customer'] as Map<String, dynamic>?;
  }

  Future<void> _openInMapsApp() async {
    if (_currentPosition == null) return;

    final customerLoc = _customerLocation;
    if (customerLoc == null) return;

    final double? customerLat = customerLoc['latitude']?.toDouble();
    final double? customerLng = customerLoc['longitude']?.toDouble();

    if (customerLat == null || customerLng == null) return;

    final url = NavigationMapService.generateGoogleMapsUrl(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      customerLat,
      customerLng,
    );

    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        final googleUrl = NavigationMapService.generateOpenStreetMapUrl(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          customerLat,
          customerLng,
        );
        if (await canLaunchUrl(Uri.parse(googleUrl))) {
          await launchUrl(Uri.parse(googleUrl));
        }
      }
    } catch (e) {
      debugPrint('Error launching maps: $e');
      _showError('Cannot open maps application');
    }
  }

  void _updateWebView(Position newPosition) {
    if (_currentPosition == null) return;

    final customerLoc = _customerLocation;
    if (customerLoc == null) return;

    final double? customerLat = customerLoc['latitude']?.toDouble();
    final double? customerLng = customerLoc['longitude']?.toDouble();

    if (customerLat == null || customerLng == null) return;

    // Update driver position in webview
    final updateScript = '''
      try {
        // Update driver marker position
        if (window.driverMarker) {
          window.driverMarker.setLatLng([${newPosition.latitude}, ${newPosition.longitude}]);
        }
        
        // Update route if routing control exists
        if (window.routingControl) {
          window.routingControl.setWaypoints([
            L.latLng(${newPosition.latitude}, ${newPosition.longitude}),
            L.latLng($customerLat, $customerLng)
          ]);
        } else {
          // Update straight line
          if (window.straightLine) {
            window.straightLine.setLatLngs([
              [${newPosition.latitude}, ${newPosition.longitude}],
              [$customerLat, $customerLng]
            ]);
          }
          
          // Update distance and time for straight line
          var newDistance = calculateStraightLineDistance(
            ${newPosition.latitude}, ${newPosition.longitude},
            $customerLat, $customerLng
          ).toFixed(1);
          
          var newEstimatedTime = Math.round(newDistance * 2);
          
          // Update route info display
          var routeInfo = document.querySelector('.route-info');
          if (routeInfo) {
            routeInfo.innerHTML = 
              '<strong>Live Tracking - Straight Line</strong><br>' +
              'Distance: ' + newDistance + ' km<br>' +
              'Est. Time: ' + newEstimatedTime + ' min<br>' +
              '<small>Updated: ' + new Date().toLocaleTimeString() + '</small>';
          }
        }
        
        // Re-center map if needed
        if (window.map && window.driverMarker && window.customerMarker) {
          var group = new L.featureGroup([window.driverMarker, window.customerMarker]);
          window.map.fitBounds(group.getBounds().pad(0.1));
        }
      } catch (error) {
        console.log('WebView update error:', error);
      }
    ''';

    _webViewController.runJavaScript(updateScript);
  }

  String _buildMapHtml() {
    if (_currentPosition == null) return '';

    final customerLoc = _customerLocation;
    if (customerLoc == null) return '';

    final double? customerLat = customerLoc['latitude']?.toDouble();
    final double? customerLng = customerLoc['longitude']?.toDouble();

    if (customerLat == null || customerLng == null) return '';

    return '''
<!DOCTYPE html>
<html>
<head>
    <title>Live Navigation Map</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.7.1/dist/leaflet.css" />
    <script src="https://unpkg.com/leaflet@1.7.1/dist/leaflet.js"></script>
    <script src="https://unpkg.com/leaflet-routing-machine@3.2.12/dist/leaflet-routing-machine.js"></script>
    <link rel="stylesheet" href="https://unpkg.com/leaflet-routing-machine@3.2.12/dist/leaflet-routing-machine.css" />
    <style>
        body { margin: 0; padding: 0; }
        #map { height: 100vh; width: 100%; }
        .route-info { 
            position: absolute; 
            top: 10px; 
            left: 10px; 
            background: white; 
            padding: 10px; 
            border-radius: 5px; 
            box-shadow: 0 2px 5px rgba(0,0,0,0.2); 
            z-index: 1000;
            font-family: Arial, sans-serif;
            max-width: 250px;
        }
        .live-indicator {
            display: inline-block;
            width: 8px;
            height: 8px;
            background: #ff4444;
            border-radius: 50%;
            margin-right: 5px;
            animation: pulse 1.5s infinite;
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.4; }
            100% { opacity: 1; }
        }
    </style>
</head>
<body>
    <div class="route-info">
        <strong><span class="live-indicator"></span>Live Navigation</strong><br>
        Calculating route...
    </div>
    <div id="map"></div>
    
    <script>
        // Store references for updates
        window.map = null;
        window.driverMarker = null;
        window.customerMarker = null;
        window.routingControl = null;
        window.straightLine = null;
        
        // Initialize map
        window.map = L.map('map').setView([${_currentPosition!.latitude}, ${_currentPosition!.longitude}], 13);
        
        // Add OpenStreetMap tiles
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '© OpenStreetMap contributors'
        }).addTo(window.map);
        
        // Driver marker (blue)
        window.driverMarker = L.marker([${_currentPosition!.latitude}, ${_currentPosition!.longitude}])
            .addTo(window.map)
            .bindPopup('<b>Your Location (Driver)</b><br>Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}<br>Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}');
        
        // Customer marker (red)
        window.customerMarker = L.marker([$customerLat, $customerLng], {icon: L.icon({
            iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
            shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
            iconSize: [25, 41],
            iconAnchor: [12, 41],
            popupAnchor: [1, -34],
            shadowSize: [41, 41]
        })}).addTo(window.map)
            .bindPopup('<b>Customer Location</b><br>Lat: $customerLat<br>Lng: $customerLng');
        
        // Calculate straight-line distance for fallback
        function calculateStraightLineDistance(lat1, lon1, lat2, lon2) {
            var R = 6371; // Earth's radius in km
            var dLat = (lat2 - lat1) * Math.PI / 180;
            var dLon = (lon2 - lon1) * Math.PI / 180;
            var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                    Math.sin(dLon/2) * Math.sin(dLon/2);
            var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
            return R * c;
        }
        
        // Try to use Leaflet Routing Machine with OSRM
        try {
            window.routingControl = L.Routing.control({
                waypoints: [
                    L.latLng(${_currentPosition!.latitude}, ${_currentPosition!.longitude}),
                    L.latLng($customerLat, $customerLng)
                ],
                routeWhileDragging: false,
                showAlternatives: false,
                fitSelectedRoutes: true,
                show: false,
                router: L.Routing.osrmv1({
                    serviceUrl: 'https://router.project-osrm.org/route/v1'
                }),
                lineOptions: {
                    styles: [
                        {color: 'blue', opacity: 0.8, weight: 6}
                    ],
                    extendToWaypoints: false,
                    missingRouteTolerance: 0
                },
                createMarker: function() { return null; }
            }).addTo(window.map);
            
            // Listen for route found event
            window.routingControl.on('routesfound', function(e) {
                var routes = e.routes;
                var summary = routes[0].summary;
                
                // Update route info
                var routeInfo = document.querySelector('.route-info');
                var distance = (summary.totalDistance / 1000).toFixed(1);
                var time = Math.round(summary.totalTime / 60);
                
                routeInfo.innerHTML = 
                    '<strong><span class="live-indicator"></span>Live Navigation</strong><br>' +
                    'Distance: ' + distance + ' km<br>' +
                    'Time: ' + time + ' min<br>' +
                    '<small>Updated: ' + new Date().toLocaleTimeString() + '</small>';
            });
            
            // Listen for routing error
            window.routingControl.on('routingerror', function(e) {
                console.error('Routing error:', e.error);
                fallbackToStraightLine();
            });
            
        } catch (error) {
            console.error('Routing initialization error:', error);
            fallbackToStraightLine();
        }
        
        // Fallback function
        function fallbackToStraightLine() {
            window.straightLine = L.polyline([
                [${_currentPosition!.latitude}, ${_currentPosition!.longitude}],
                [$customerLat, $customerLng]
            ], {
                color: 'red',
                weight: 4,
                opacity: 0.7,
                dashArray: '10, 10'
            }).addTo(window.map);
            
            updateStraightLineInfo();
        }
        
        function updateStraightLineInfo() {
            if (!window.driverMarker || !window.customerMarker) return;
            
            var driverLatLng = window.driverMarker.getLatLng();
            var customerLatLng = window.customerMarker.getLatLng();
            
            var distance = calculateStraightLineDistance(
                driverLatLng.lat, driverLatLng.lng,
                customerLatLng.lat, customerLatLng.lng
            ).toFixed(1);
            
            var estimatedTime = Math.round(distance * 2); // Rough estimate: 2 min per km
            
            // Update route info
            var routeInfo = document.querySelector('.route-info');
            if (routeInfo) {
                routeInfo.innerHTML = 
                    '<strong><span class="live-indicator"></span>Live Navigation</strong><br>' +
                    'Distance: ' + distance + ' km<br>' +
                    'Est. Time: ' + estimatedTime + ' min<br>' +
                    '<small>Updated: ' + new Date().toLocaleTimeString() + '</small>';
            }
        }
        
        // Initial fit to markers
        var group = new L.featureGroup([window.driverMarker, window.customerMarker]);
        window.map.fitBounds(group.getBounds().pad(0.1));
    </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final customerLoc = _customerLocation;
    final double? customerLat = customerLoc?['latitude']?.toDouble();
    final double? customerLng = customerLoc?['longitude']?.toDouble();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _isRealTimeActive ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              'Live Navigation',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isRealTimeActive ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _isRealTimeActive = !_isRealTimeActive;
              });
            },
            tooltip: _isRealTimeActive ? 'Pause Updates' : 'Resume Updates',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Getting your location...'),
          ],
        ),
      )
          : Column(
        children: [
          // Real-time Route Information Card
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem(
                  Icons.place,
                  'Live Distance',
                  '${_distance?.toStringAsFixed(1) ?? '--'} km',
                ),
                _buildInfoItem(
                  Icons.timer,
                  'Est. Time',
                  '${_estimatedTime ?? '--'} min',
                ),
                _buildInfoItem(
                  Icons.update,
                  'Status',
                  _isRealTimeActive ? 'Live' : 'Paused',
                  valueColor: _isRealTimeActive ? Colors.green : Colors.orange,
                ),
              ],
            ),
          ),

          // Map Section
          Expanded(
            child: _currentPosition != null && customerLat != null && customerLng != null
                ? WebViewWidget(
              controller: _webViewController = WebViewController()
                ..setJavaScriptMode(JavaScriptMode.unrestricted)
                ..loadHtmlString(_buildMapHtml()),
            )
                : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map, size: 80, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    'Map Unavailable',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('Location data not available'),
                ],
              ),
            ),
          ),

          // Action Buttons
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openInMapsApp,
                    icon: Icon(Icons.navigation, size: 20),
                    label: Text('Open in Maps App'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                if (widget.request['contactNumber'] != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final phone = widget.request['contactNumber'];
                        if (phone != null) {
                          launchUrl(Uri.parse('tel:$phone'));
                        }
                      },
                      icon: Icon(Icons.phone, size: 20),
                      label: Text('Call Customer'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: BorderSide(color: Colors.green),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value, {Color? valueColor}) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 24),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.blue,
          ),
        ),
      ],
    );
  }
}