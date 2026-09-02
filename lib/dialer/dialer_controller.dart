import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../voice_service.dart';
import '../audio_stream_service.dart';

enum CallStatus { idle, dialing, ringing, inCall, ended }

class DialerController extends ChangeNotifier {
  static const MethodChannel _telecomChannel = MethodChannel(
    'com.example.telicall_voice_app/telecom',
  );
  final VoiceService voiceService = VoiceService();

  static const String baseUrl = "http://192.168.1.21:8000";

  int currentTabIndex = 0;
  bool isAiCallingMode = false;
  String selectedStatusFilter = "PENDING";
  String reportRange = "daily";

  String dialedNumber = "";
  int? activeLeadId;
  bool isCallActive = false;
  bool isDialingOut = false;

  CallStatus callStatus = CallStatus.idle;
  final List<Map<String, String>> liveTranscripts = [];
  Timer? _callTimer;
  int callDurationSeconds = 0;

  List<fc.Contact> deviceContacts = [];
  List<fc.Contact> filteredContacts = [];
  bool isLoadingContacts = false;
  bool hasContactsPermission = false;
  final TextEditingController searchController = TextEditingController();

  final List<CallLogModel> recentCallsList = [];
  List<ContactQueueItem> aiCallQueue = [];
  bool isLoadingQueue = false;

  bool isAutoDialing = false;
  Timer? _autoDialTimer;

  Map<String, dynamic> analyticsData = {
    'total_called': 0,
    'total_pending': 0,
    'total_followup': 0,
    'most_asked_questions': [],
  };

  DialerController() {
    _initVoiceServiceCallbacks();
    requestDefaultDialerStatus();
    loadDeviceContacts();
    fetchAiCallQueue();
    fetchAnalyticsReports();
    searchController.addListener(filterContactsList);
  }

  // void _setupNativeTelecomListener() {
  //   _telecomChannel.setMethodCallHandler((call) async {
  //     switch (call.method) {
  //       case 'onCallAnswered':
  //         if (isCallActive && isAiCallingMode) {
  //           voiceService.notifyCallAnswered();
  //         }
  //         break;
  //       case 'onCallEnded':
  //         handleCallEndedState();
  //         break;
  //     }
  //   });
  // }

  void _initVoiceServiceCallbacks() {
    voiceService.onTokenReceived = (token) {
      if (isAiCallingMode) {
        if (liveTranscripts.isEmpty || liveTranscripts.last['sender'] != 'AI') {
          liveTranscripts.add({'sender': 'AI', 'text': token});
        } else {
          liveTranscripts.last['text'] =
              (liveTranscripts.last['text'] ?? '') + token;
        }

        notifyListeners();
      }
    };

    voiceService.onTranscriptReceived = (sender, text) {
      if (isAiCallingMode) {
        liveTranscripts.add({'sender': sender, 'text': text});

        if (callStatus == CallStatus.ringing ||
            callStatus == CallStatus.dialing) {
          callStatus = CallStatus.inCall;
          startCallTimer();
        }

        notifyListeners();
      }
    };

    voiceService.onStateChanged = (isConnected) {
      if (!isConnected && isCallActive) {
        handleCallEndedState();
      }
    };

    voiceService.onCallAnswered = () {
      debugPrint('📞 DialerController: onCallAnswered');

      if (isCallActive && isAiCallingMode) {
        if (callStatus != CallStatus.inCall) {
          callStatus = CallStatus.inCall;
          startCallTimer();
          notifyListeners();
        }
      }
    };

    voiceService.onCallEnded = () {
      debugPrint('📴 DialerController: onCallEnded');

      if (isCallActive) {
        handleCallEndedState();
      }
    };
  }

  Future<void> requestDefaultDialerStatus() async {
    try {
      await _telecomChannel.invokeMethod('requestDefaultDialer');
    } catch (e) {
      debugPrint("❌ Failed to request default dialer status: $e");
    }
  }

  void setTabIndex(int index) {
    if (!isCallActive) {
      currentTabIndex = index;
      notifyListeners();
    }
  }

  void toggleAiMode(bool aiMode) {
    if (!isCallActive) {
      isAiCallingMode = aiMode;
      currentTabIndex = 0;
      notifyListeners();
    }
  }

  void appendKeypadDigit(String label) {
    if (dialedNumber.length < 15) {
      dialedNumber += label;
      notifyListeners();
    }
  }

  void backspaceKeypadDigit() {
    if (dialedNumber.isNotEmpty) {
      dialedNumber = dialedNumber.substring(0, dialedNumber.length - 1);
      notifyListeners();
    }
  }

  void startCallTimer() {
    callDurationSeconds = 0;
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      callDurationSeconds++;
      notifyListeners();
    });
  }

  void stopCallTimer() {
    _callTimer?.cancel();
  }

  String formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$mins:$secs";
  }

  void handleCallEndedState() {
    stopCallTimer();
    callStatus = CallStatus.ended;
    notifyListeners();

    Future.delayed(const Duration(seconds: 2), () {
      isCallActive = false;
      isDialingOut = false;
      callStatus = CallStatus.idle;
      notifyListeners();
    });
  }

  Future<void> loadDeviceContacts() async {
    isLoadingContacts = true;
    notifyListeners();

    try {
      final permission = await fc.FlutterContacts.permissions.request(
        fc.PermissionType.read,
      );

      if (permission == fc.PermissionStatus.granted) {
        final contacts = await fc.FlutterContacts.getAll(
          properties: {fc.ContactProperty.name, fc.ContactProperty.phone},
        );

        deviceContacts = contacts;
        filteredContacts = List<fc.Contact>.from(contacts);
        hasContactsPermission = true;
      } else {
        hasContactsPermission = false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Contact loading error: $e');
      debugPrint('$stackTrace');
      hasContactsPermission = false;
    }

    isLoadingContacts = false;
    notifyListeners();
  }

  void filterContactsList() {
    final query = searchController.text.toLowerCase().trim();

    if (query.isEmpty) {
      filteredContacts = List<fc.Contact>.from(deviceContacts);
      notifyListeners();
      return;
    }

    filteredContacts = deviceContacts.where((contact) {
      final name = (contact.displayName ?? '').toLowerCase();

      final phoneNumbers = contact.phones.map((phone) {
        return phone.number.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      });

      return name.contains(query) ||
          phoneNumbers.any((number) => number.contains(query));
    }).toList();

    notifyListeners();
  }

  Future<void> fetchAiCallQueue([String? statusFilter]) async {
    final String filter = (statusFilter ?? selectedStatusFilter).toUpperCase();

    // Immediately update selected tab
    selectedStatusFilter = filter;

    isLoadingQueue = true;
    notifyListeners();

    try {
      final uri = Uri.parse("$baseUrl/api/call-queue/?status=$filter");

      debugPrint("========================================");
      debugPrint("📡 FETCH CALL QUEUE");
      debugPrint("🌐 URL: $uri");
      debugPrint("📊 STATUS: $filter");
      debugPrint("========================================");

      final response = await http
          .get(uri, headers: {"Accept": "application/json"})
          .timeout(const Duration(seconds: 10));

      debugPrint("📥 Queue response: ${response.statusCode}");

      debugPrint("📦 Queue body: ${response.body}");

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is List) {
          aiCallQueue = decoded
              .map(
                (item) =>
                    ContactQueueItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList();

          debugPrint("✅ Loaded ${aiCallQueue.length} $filter records");
        } else {
          debugPrint("⚠️ API did not return a List");

          aiCallQueue = [];
        }
      } else {
        debugPrint("❌ Queue API error: ${response.statusCode}");

        aiCallQueue = [];
      }
    } catch (e, stackTrace) {
      debugPrint("❌ Queue request failed: $e");

      debugPrint("📍 $stackTrace");

      aiCallQueue = [];
    } finally {
      isLoadingQueue = false;
      notifyListeners();
    }
  }

  Future<void> fetchAnalyticsReports() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/reports/?range=$reportRange"),
      );
      if (response.statusCode == 200) {
        analyticsData = jsonDecode(response.body);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("❌ Error fetching analytics: $e");
    }
  }

  Future<void> addNewLead(String name, String phone, String details) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/call-queue/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "phone_number": phone,
          "details": details,
        }),
      );
      if (response.statusCode == 201) {
        fetchAiCallQueue("PENDING");
      }
    } catch (e) {
      debugPrint("❌ Error adding lead: $e");
    }
  }

  Future<void> updateLeadStatus(int id, String status) async {
    final newStatus = status.toUpperCase();

    try {
      debugPrint("========================================");
      debugPrint("🔄 UPDATE LEAD STATUS");
      debugPrint("🆔 Lead ID: $id");
      debugPrint("📊 New status: $newStatus");
      debugPrint("========================================");

      final response = await http
          .patch(
            Uri.parse("$baseUrl/api/call-queue/$id/update/"),
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode({"status": newStatus}),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint("📥 Status update response: ${response.statusCode}");

      debugPrint("📦 Response: ${response.body}");

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint("✅ Lead $id changed to $newStatus");

        // Reload the currently selected tab.
        await fetchAiCallQueue(selectedStatusFilter);

        // Refresh dashboard numbers.
        await fetchAnalyticsReports();
      } else {
        debugPrint(
          "❌ Status update failed: "
          "${response.statusCode}",
        );
      }
    } catch (e, stackTrace) {
      debugPrint("❌ Error updating lead status: $e");

      debugPrint("📍 $stackTrace");
    }
  }

  Future<void> downloadReportCSV() async {
    final Uri url = Uri.parse("$baseUrl/api/reports/export/");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void toggleAutoDialer() {
    if (isAutoDialing) {
      stopAutoDialer();
    } else {
      if (aiCallQueue.isEmpty) return;
      isAutoDialing = true;
      notifyListeners();
      dialNextInQueue();
    }
  }

  void stopAutoDialer() {
    _autoDialTimer?.cancel();
    isAutoDialing = false;
    notifyListeners();
  }

  void dialNextInQueue() {
    if (!isAutoDialing) return;
    final pendingItems = aiCallQueue
        .where((item) => item.status == "PENDING")
        .toList();
    if (pendingItems.isEmpty) {
      stopAutoDialer();
      return;
    }
    final currentLead = pendingItems.first;
    executeCall(
      currentLead.phoneNumber,
      leadId: currentLead.id,
      contactName: currentLead.name,
      details: currentLead.details,
    );
  }

  Future<void> executeCall(
    String number, {
    int? leadId,
    String? contactName,
    String? details,
  }) async {
    if (number.trim().isEmpty) return;
    final String cleanNumber = number.replaceAll(RegExp(r'[^\d+]'), '');

    try {
      final Map<Permission, PermissionStatus> permissions = await [
        Permission.phone,
        Permission.microphone,
      ].request();

      if (permissions[Permission.phone]?.isGranted != true) return;
    } catch (e) {
      debugPrint("⚠️ Permission warning: $e");
    }

    dialedNumber = cleanNumber;
    activeLeadId = leadId;
    isCallActive = true;
    isDialingOut = true;
    callStatus = CallStatus.dialing;
    liveTranscripts.clear();
    notifyListeners();

    recentCallsList.insert(
      0,
      CallLogModel(
        name: contactName ?? cleanNumber,
        phoneNumber: cleanNumber,
        time: "Just now",
        callType: "Outgoing",
      ),
    );

    String backendHost = " 10.82.144.248:8000";
    try {
      final Uri parsedUri = Uri.parse(baseUrl);
      if (parsedUri.authority.isNotEmpty) backendHost = parsedUri.authority;
    } catch (_) {}

    try {
      await _telecomChannel.invokeMethod<bool>('makeNativeInternalCall', {
        'phoneNumber': cleanNumber,
        'isAiMode': isAiCallingMode,
      });

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (callStatus == CallStatus.dialing) {
          callStatus = CallStatus.ringing;
          notifyListeners();
        }
      });

      if (isAiCallingMode) {
        Future.delayed(const Duration(seconds: 3), () async {
          if (isCallActive) {
            AudioStreamService().startAudioStreaming();
            voiceService.connectToBackend(
              backendHost,
              cleanNumber,
              details: details ?? "",
            );
            voiceService.syncHardwareCallState("OFFHOOK");
            await _telecomChannel.invokeMethod('setAudioMode', {
              'isAiMode': true,
            });
            callStatus = CallStatus.inCall;
            startCallTimer();
            notifyListeners();
          }
        });
      } else {
        Future.delayed(const Duration(seconds: 2), () {
          if (isCallActive) {
            callStatus = CallStatus.inCall;
            startCallTimer();
            notifyListeners();
          }
        });
      }
    } catch (e) {
      endCallSession(isUserAction: true);
      return;
    }

    Future.delayed(const Duration(seconds: 5), () {
      isDialingOut = false;
      notifyListeners();
    });
  }

  void endCallSession({bool isUserAction = false}) async {
    if (isDialingOut && isCallActive && !isUserAction) return;

    try {
      await _telecomChannel.invokeMethod('disconnectCall');
    } catch (_) {}

    if (isAiCallingMode) {
      voiceService.syncHardwareCallState("IDLE");
      voiceService.disconnectSession();
      AudioStreamService().stopAudioStreaming();
      if (activeLeadId != null) {
        updateLeadStatus(activeLeadId!, "CALLED");
      }
    }

    handleCallEndedState();

    if (isAutoDialing) {
      _autoDialTimer = Timer(const Duration(seconds: 4), () {
        if (isAutoDialing && !isCallActive) {
          dialNextInQueue();
        }
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    _callTimer?.cancel();
    _autoDialTimer?.cancel();
    super.dispose();
  }
}
