import 'package:flutter/material.dart';

import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/dashcam/screens/dashcam_screen.dart';
import '../../features/driver_monitor/screens/driver_monitor_screen.dart';
import '../../features/navigation/screens/live_driving_screen.dart';
import '../../features/navigation/screens/navigation_screen.dart';
import '../../features/parking/screens/parking_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/authentication/screens/splash_screen.dart';
import '../../features/authentication/screens/onboarding_screen.dart';
import '../../features/vehicle/screens/vehicle_screen.dart';
import '../../features/dashboard/screens/trips_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String dashboard = '/dashboard';
  static const String liveDriving = '/live-driving';
  static const String navigation = '/navigation';
  static const String dashcam = '/dashcam';
  static const String parking = '/parking';
  static const String trips = '/trips';
  static const String vehicle = '/vehicle';
  static const String driverMonitor = '/driver-monitor';
  static const String settings = '/settings';

  static Map<String, WidgetBuilder> get routes => {
        splash: (_) => const SplashScreen(),
        onboarding: (_) => const OnboardingScreen(),
        dashboard: (_) => const DashboardScreen(),
        liveDriving: (_) => const LiveDrivingScreen(),
        navigation: (_) => const NavigationScreen(),
        dashcam: (_) => const DashcamScreen(),
        parking: (_) => const ParkingScreen(),
        trips: (_) => const TripsScreen(),
        vehicle: (_) => const VehicleScreen(),
        driverMonitor: (_) => const DriverMonitorScreen(),
        settings: (_) => const SettingsScreen(),
      };
}
