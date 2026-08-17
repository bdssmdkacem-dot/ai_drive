import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/themes/app_theme.dart';
import '../../voice/services/voice_assistant_service.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key, this.embedded = false});

  /// When true, this widget is shown as a tab inside [DashboardScreen].
  final bool embedded;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  static const _fallbackLocation = LatLng(33.5731, -7.5898); // Casablanca

  LatLng? _current;
  GoogleMapController? _mapController;
  final _voice = VoiceAssistantService();

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    try {
      final pos = await Geolocator.getCurrentPosition();
      final location = LatLng(pos.latitude, pos.longitude);

      if (!mounted) return;
      setState(() => _current = location);

      final controller = _mapController;
      if (controller != null) {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: location, zoom: 15),
          ),
        );
      }
    } catch (_) {
      // The map remains usable at the Morocco fallback location.
    }
  }

  Future<void> _startVoiceCommand() async {
    await _voice.init();
    await _voice.startListening(
      onCommand: (text) {
        final intent = VoiceCommandParser.parse(text);
        _handleIntent(intent);
      },
    );
  }

  void _handleIntent(VoiceIntent intent) {
    switch (intent) {
      case VoiceIntent.navigateHome:
        _navigateToSavedAddress('home_address', 'المنزل');
        break;
      case VoiceIntent.navigateWork:
        _navigateToSavedAddress('work_address', 'العمل');
        break;
      case VoiceIntent.nearestGasStation:
        _voice.speak('جاري البحث عن أقرب محطة وقود');
        _launchMapSearch('gas station');
        break;
      case VoiceIntent.nearestParking:
        _voice.speak('جاري البحث عن أقرب موقف سيارات');
        _launchMapSearch('parking');
        break;
      case VoiceIntent.cancelRoute:
        _voice.speak('تم إلغاء الطريق');
        break;
      default:
        _voice.speak('لم أفهم الأمر');
    }
  }

  Future<void> _navigateToSavedAddress(
    String prefKey,
    String spokenLabel,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(prefKey);
    if (address == null || address.trim().isEmpty) {
      await _voice.speak('لم يتم تعيين عنوان $spokenLabel بعد. أضفه من الإعدادات');
      return;
    }

    await _voice.speak('جارٍ التوجه إلى $spokenLabel');
    await _launchMapSearch(address);
  }

  Future<void> _launchMapSearch(String query) async {
    final uri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _current ?? _fallbackLocation,
            zoom: 13,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            final location = _current;
            if (location != null) {
              controller.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: location, zoom: 15),
                ),
              );
            }
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: false,
          compassEnabled: true,
          mapToolbarEnabled: false,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            backgroundColor: AppTheme.primary,
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.liveDriving);
            },
            child: const Icon(Icons.navigation, color: Colors.black),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'voice-fab',
            backgroundColor: AppTheme.surface,
            onPressed: _startVoiceCommand,
            child: const Icon(Icons.mic, color: AppTheme.primary),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Navigation')),
      body: body,
    );
  }
}
