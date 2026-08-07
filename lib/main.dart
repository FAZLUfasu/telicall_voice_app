// import 'package:flutter/material.dart';
// import 'main_dialer_screen.dart';

// void main() {
//   WidgetsFlutterBinding.ensureInitialized();
//   runApp(const TelicallVoiceApp());
// }

// class TelicallVoiceApp extends StatelessWidget {
//   const TelicallVoiceApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Telicall AI Dialer',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData.dark().copyWith(
//         scaffoldBackgroundColor: const Color(0xFF121212),
//         primaryColor: Colors.deepPurple,
//         appBarTheme: const AppBarTheme(
//           backgroundColor: Color(0xFF1E1E1E),
//           elevation: 0,
//         ),
//       ),
//       home: const MainDialerContainer(),

//       onUnknownRoute: (settings) {
//         debugPrint("📱 Intercepted unknown route/intent: ${settings.name}");
//         return MaterialPageRoute(
//           builder: (context) => const MainDialerContainer(),
//         );
//       },
//       onGenerateRoute: (settings) {
//         return MaterialPageRoute(
//           builder: (context) => const MainDialerContainer(),
//         );
//       },
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'main_dialer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TelicallVoiceApp());
}

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
      home: const MainDialerContainer(),
      onUnknownRoute: (settings) {
        debugPrint("📱 Intercepted unknown route/intent: ${settings.name}");
        return MaterialPageRoute(
          builder: (context) => const MainDialerContainer(),
        );
      },
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => const MainDialerContainer(),
        );
      },
    );
  }
}
