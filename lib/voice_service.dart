import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'call_web_socket_service.dart';

class VoiceService {
  // ================================================================
  // SINGLETON
  // ================================================================

  static final VoiceService _instance = VoiceService._internal();

  factory VoiceService() => _instance;

  VoiceService._internal();

  // ================================================================
  // ANDROID METHOD CHANNEL
  // ================================================================

  static const MethodChannel _telecomChannel = MethodChannel(
    'com.example.telicall_voice_app/telecom',
  );

  // ================================================================
  // WEBSOCKET
  // ================================================================

  WebSocketChannel? _channel;

  bool _isConnected = false;

  bool _pendingCallAnswered = false;

  bool _nativeListenersInitialized = false;

  // ================================================================
  // AI AUDIO INJECTOR
  // ================================================================

  final CallWebSocketService _audioInjectorService = CallWebSocketService();

  // ================================================================
  // UI CALLBACKS
  // ================================================================

  Function(String token)? onTokenReceived;

  Function(String sender, String text)? onTranscriptReceived;

  Function(bool isConnected)? onStateChanged;

  VoidCallback? onCallAnswered;

  VoidCallback? onCallEnded;

  // ================================================================
  // GETTERS
  // ================================================================

  bool get isConnected => _isConnected;

  // ================================================================
  // INITIALIZE NATIVE METHODCHANNEL LISTENER
  // ================================================================

  void initializeNativeListeners() {
    if (_nativeListenersInitialized) {
      debugPrint("VoiceService native listener already initialized.");
      return;
    }

    _nativeListenersInitialized = true;

    debugPrint("==========================================");
    debugPrint("VoiceService native listener initializing");
    debugPrint("==========================================");

    _telecomChannel.setMethodCallHandler((MethodCall call) async {
      debugPrint("Native event received: ${call.method}");

      switch (call.method) {
        // ========================================================
        // CALL ANSWERED
        // ========================================================
        case 'onCallAnswered':
          debugPrint("CALL ANSWERED event received from Android");

          notifyCallAnswered();

          onCallAnswered?.call();

          return true;

        // ========================================================
        // CALL ENDED
        // ========================================================
        case 'onCallEnded':
          debugPrint("CALL ENDED event received from Android");

          onCallEnded?.call();

          disconnectSession();

          return true;

        // ========================================================
        // CUSTOMER VOICE FROM ANDROID VOICE_DOWNLINK
        // ========================================================
        case 'onCustomerDownlinkAudioReceived':
          debugPrint("CUSTOMER DOWNLINK EVENT RECEIVED IN VOICESERVICE");

          final bool sent = _handleCustomerDownlinkAudio(call.arguments);

          return sent;

        // ========================================================
        // AI RESPONSE FILE CREATED
        // ========================================================
        case 'onAiResponseAudioCreated':
          debugPrint("AI response recording created:");
          debugPrint("${call.arguments}");

          return true;

        // ========================================================
        // CUSTOMER RECORDING CREATED
        // ========================================================
        case 'onNewChunkSaved':
          debugPrint("Customer audio recording saved:");
          debugPrint("${call.arguments}");

          return true;

        // ========================================================
        // UNKNOWN EVENT
        // ========================================================
        default:
          debugPrint("Unhandled native MethodChannel event: ${call.method}");

          return null;
      }
    });

    debugPrint("VoiceService native listener initialized");
  }

  // ================================================================
  // HANDLE CUSTOMER DOWNLINK PCM
  // ================================================================

  bool _handleCustomerDownlinkAudio(dynamic arguments) {
    debugPrint("==========================================");
    debugPrint("CUSTOMER DOWNLINK CALLBACK ENTERED");
    debugPrint("Native argument type: ${arguments.runtimeType}");

    Uint8List? pcmBytes;

    if (arguments is Uint8List) {
      pcmBytes = arguments;
    } else if (arguments is List<int>) {
      pcmBytes = Uint8List.fromList(arguments);
    } else {
      debugPrint("Invalid CUSTOMER PCM type: ${arguments.runtimeType}");

      return false;
    }

    if (pcmBytes.isEmpty) {
      debugPrint("CUSTOMER PCM is EMPTY");

      return false;
    }

    debugPrint(
      "CUSTOMER DOWNLINK -> FLUTTER | "
      "bytes=${pcmBytes.length}",
    );

    debugPrint(
      "WEBSOCKET STATE | "
      "connected=$_isConnected | "
      "channel=${_channel != null}",
    );

    if (!_isConnected) {
      debugPrint(
        "CUSTOMER PCM CANNOT BE SENT | "
        "backend disconnected",
      );

      return false;
    }

    if (_channel == null) {
      debugPrint(
        "CUSTOMER PCM CANNOT BE SENT | "
        "WebSocket channel NULL",
      );

      return false;
    }

    final bool sent = sendCustomerAudioChunk(pcmBytes);

    debugPrint(
      "CUSTOMER PCM -> WS | "
      "bytes=${pcmBytes.length} | "
      "sent=$sent",
    );

    debugPrint("==========================================");

    return sent;
  }

  // ================================================================
  // SEND CUSTOMER PCM TO BACKEND
  // ================================================================

  bool sendCustomerAudioChunk(Uint8List pcmBytes) {
    debugPrint(
      "SEND CHECK | "
      "connected=$_isConnected | "
      "channel=${_channel != null} | "
      "bytes=${pcmBytes.length}",
    );

    if (pcmBytes.isEmpty) {
      debugPrint("CUSTOMER PCM NOT SENT: empty PCM buffer");

      return false;
    }

    if (!_isConnected) {
      debugPrint("CUSTOMER PCM NOT SENT: WebSocket disconnected");

      return false;
    }

    final WebSocketChannel? channel = _channel;

    if (channel == null) {
      debugPrint("CUSTOMER PCM NOT SENT: WebSocket channel NULL");

      return false;
    }

    try {
      // Send RAW PCM as a binary WebSocket frame.
      channel.sink.add(pcmBytes);

      debugPrint(
        "CUSTOMER PCM -> BACKEND | "
        "${pcmBytes.length} bytes",
      );

      return true;
    } catch (e, stackTrace) {
      debugPrint("CUSTOMER PCM SEND ERROR: $e");

      debugPrint("$stackTrace");

      return false;
    }
  }

  // ================================================================
  // CONNECT TO BACKEND
  // ================================================================

  void connectToBackend(
    String serverIp,
    String clientNumber, {
    String? details,
  }) {
    if (_isConnected || _channel != null) {
      debugPrint("Existing WebSocket session found. Closing first.");

      disconnectSession();
    }

    String cleanHost = serverIp.replaceAll(RegExp(r'^https?://|^wss?://'), '');

    if (cleanHost.endsWith('/')) {
      cleanHost = cleanHost.substring(0, cleanHost.length - 1);
    }

    /*
     * Local Django development server.
     */
    if (!cleanHost.contains(':') && !cleanHost.contains('ngrok')) {
      cleanHost = "$cleanHost:8000";
    }

    final String wsUrl = "ws://$cleanHost/ws/media-stream/";

    debugPrint("==========================================");
    debugPrint("CONNECTING TO BACKEND");
    debugPrint(wsUrl);
    debugPrint("==========================================");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _isConnected = true;

      onStateChanged?.call(true);

      debugPrint("WebSocket connection created");

      // ============================================================
      // SEND INITIAL CUSTOMER / LEAD DATA
      // ============================================================

      _channel!.sink.add(
        jsonEncode({
          "client_phone_number": clientNumber,
          "lead_details": details ?? "",
        }),
      );

      debugPrint("Customer metadata -> backend");

      // ============================================================
      // FLUSH PENDING CALL ANSWER EVENT
      // ============================================================

      if (_pendingCallAnswered) {
        debugPrint("Flushing queued call_answered event");

        notifyCallAnswered();
      }

      // ============================================================
      // RECEIVE BACKEND DATA
      // ============================================================

      _channel!.stream.listen(
        _handleBackendMessage,
        onError: (error) {
          debugPrint("WebSocket error: $error");

          disconnectSession();
        },
        onDone: () {
          debugPrint("WebSocket connection closed by server");

          disconnectSession();
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint("WebSocket connection exception: $e");

      disconnectSession();
    }
  }

  // ================================================================
  // RECEIVE MESSAGE FROM BACKEND
  // ================================================================

  void _handleBackendMessage(dynamic message) {
    // ==============================================================
    // BINARY PCM = AI VOICE
    // ==============================================================

    if (message is Uint8List) {
      debugPrint(
        "BACKEND AI PCM -> FLUTTER | "
        "bytes=${message.length}",
      );

      _sendAiPcmToAndroid(message);

      return;
    }

    // ==============================================================
    // LIST<int> FALLBACK
    // ==============================================================

    if (message is List<int>) {
      final Uint8List pcmBytes = Uint8List.fromList(message);

      debugPrint(
        "BACKEND AI PCM -> FLUTTER | "
        "bytes=${pcmBytes.length}",
      );

      _sendAiPcmToAndroid(pcmBytes);

      return;
    }

    // ==============================================================
    // TEXT / JSON
    // ==============================================================

    if (message is String) {
      _handleBackendTextMessage(message);

      return;
    }

    debugPrint(
      "Unknown backend message type: "
      "${message.runtimeType}",
    );
  }

  // ================================================================
  // SEND AI PCM TO ANDROID CALL INJECTOR
  // ================================================================

  void _sendAiPcmToAndroid(Uint8List pcmBytes) {
    if (pcmBytes.isEmpty) {
      return;
    }

    try {
      debugPrint(
        "AI PCM -> CallWebSocketService | "
        "bytes=${pcmBytes.length}",
      );

      _audioInjectorService.onReceiveTtsAudioChunk(pcmBytes);
    } catch (e) {
      debugPrint("Failed forwarding AI PCM to injector: $e");
    }
  }

  // ================================================================
  // HANDLE TEXT MESSAGE FROM BACKEND
  // ================================================================

  void _handleBackendTextMessage(String message) {
    try {
      final dynamic decoded = jsonDecode(message);

      if (decoded is! Map<String, dynamic>) {
        debugPrint("Backend text: $message");

        onTokenReceived?.call(message);

        return;
      }

      final Map<String, dynamic> data = decoded;

      // ============================================================
      // BASE64 AI AUDIO
      // ============================================================

      if (data['event'] == 'audio' && data['pcm_base64'] != null) {
        try {
          final Uint8List pcmBytes = base64Decode(
            data['pcm_base64'].toString(),
          );

          debugPrint(
            "BASE64 AI PCM -> FLUTTER | "
            "bytes=${pcmBytes.length}",
          );

          _sendAiPcmToAndroid(pcmBytes);
        } catch (e) {
          debugPrint("Invalid BASE64 AI PCM: $e");
        }

        return;
      }

      // ============================================================
      // AI TOKEN
      // ============================================================

      if (data['event'] == 'ai_token' || data['type'] == 'ai_token') {
        final String token =
            data['text']?.toString() ?? data['token']?.toString() ?? '';

        if (token.isNotEmpty) {
          onTokenReceived?.call(token);
        }

        return;
      }

      // ============================================================
      // CUSTOMER TRANSCRIPT
      // ============================================================

      if (data['event'] == 'user_transcript' ||
          data['type'] == 'user_transcript') {
        final String text = data['text']?.toString() ?? '';

        if (text.isNotEmpty) {
          debugPrint("CUSTOMER: $text");

          onTranscriptReceived?.call("Customer", text);
        }

        return;
      }

      // ============================================================
      // AI RESPONSE TEXT
      // ============================================================

      if (data['event'] == 'ai_response' || data['type'] == 'ai_response') {
        final String text = data['text']?.toString() ?? '';

        if (text.isNotEmpty) {
          debugPrint("AI: $text");

          onTranscriptReceived?.call("AI", text);
        }

        return;
      }

      // ============================================================
      // OTHER BACKEND EVENT
      // ============================================================

      debugPrint("Backend JSON event: $data");
    } catch (e) {
      /*
       * Backend sent normal text instead of JSON.
       */

      debugPrint("Backend text message: $message");

      onTokenReceived?.call(message);
    }
  }

  // ================================================================
  // CALL ANSWERED
  // ================================================================

  void notifyCallAnswered() {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(
          jsonEncode({"event": "call_answered", "status": "ACTIVE"}),
        );

        _pendingCallAnswered = false;

        debugPrint("call_answered -> backend");
      } catch (e) {
        debugPrint("Failed sending call_answered: $e");

        _pendingCallAnswered = true;
      }
    } else {
      debugPrint("WebSocket not ready. Queueing call_answered.");

      _pendingCallAnswered = true;
    }
  }

  // ================================================================
  // SYNC CALL STATE
  // ================================================================

  void syncHardwareCallState(String state) {
    if (_channel == null || !_isConnected) {
      return;
    }

    try {
      _channel!.sink.add(
        jsonEncode({"event": "call_state_changed", "state": state}),
      );

      debugPrint("CALL STATE -> BACKEND: $state");
    } catch (e) {
      debugPrint("Failed sending call state: $e");
    }
  }

  // ================================================================
  // DISCONNECT SESSION
  // ================================================================

  void disconnectSession() {
    /*
     * Avoid unnecessary repeated disconnect handling.
     */
    if (_channel == null && !_isConnected) {
      _pendingCallAnswered = false;

      return;
    }

    debugPrint("==========================================");
    debugPrint("DISCONNECTING VOICE SESSION");
    debugPrint("==========================================");

    final WebSocketChannel? oldChannel = _channel;

    _channel = null;

    _isConnected = false;

    _pendingCallAnswered = false;

    onStateChanged?.call(false);

    try {
      oldChannel?.sink.close();
    } catch (e) {
      debugPrint("Error closing WebSocket: $e");
    }

    debugPrint("VoiceService session disconnected");
  }
}
