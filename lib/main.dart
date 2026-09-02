import 'package:flutter/material.dart';
import 'package:telicall_voice_app/voice_service.dart';

import 'dialer/dialer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // IMPORTANT:
  // Register Android → Flutter telecom callbacks before app startup.
  VoiceService().initializeNativeListeners();

  runApp(const TelicallVoiceApp());
}

/// Root Widget for the Telicall AI Dialer application.
class TelicallVoiceApp extends StatelessWidget {
  const TelicallVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telicall AI Dialer',
      debugShowCheckedModeBanner: false,

      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.deepPurple,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
      ),

      home: const MainDialerScreen(),

      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => const MainDialerScreen(),
        );
      },

      onUnknownRoute: (settings) {
        debugPrint("📱 Intercepted unknown route/intent: ${settings.name}");

        return MaterialPageRoute(
          builder: (context) => const MainDialerScreen(),
        );
      },
    );
  }
}
