import 'package:flutter/material.dart';

import 'core/routes/app_routes.dart';
import 'core/themes/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AiDriveApp());
}

class AiDriveApp extends StatelessWidget {
  const AiDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Drive Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
      supportedLocales: const [Locale('ar'), Locale('en')],
    );
  }
}
