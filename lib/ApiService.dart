import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiService {
  /// Checks if Django backend and AI models are fully initialized
  static Future<bool> checkBackendReadiness(String serverIp) async {
    try {
      String cleanHost = serverIp.replaceAll(
        RegExp(r'^https?://|^wss?://'),
        '',
      );
      if (cleanHost.endsWith('/')) {
        cleanHost = cleanHost.substring(0, cleanHost.length - 1);
      }
      if (!cleanHost.contains(':') && !cleanHost.contains('ngrok')) {
        cleanHost = "$cleanHost:8000";
      }

      final String statusUrl = "http://$cleanHost/api/status/";
      debugPrint("🔍 Checking backend status at $statusUrl...");

      final response = await http
          .get(Uri.parse(statusUrl))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        debugPrint("✅ Backend AI engines are fully loaded!");
        return true;
      }
    } catch (e) {
      debugPrint("⏳ Backend is still initializing or unreachable: $e");
    }
    return false;
  }
}
