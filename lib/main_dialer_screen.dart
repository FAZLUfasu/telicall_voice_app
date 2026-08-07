import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide PermissionStatus;
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'voice_service.dart';
import 'audio_stream_service.dart';

enum CallStatus { idle, dialing, ringing, inCall, ended }

class MainDialerContainer extends StatefulWidget {
  const MainDialerContainer({super.key});

  @override
  State<MainDialerContainer> createState() => _MainDialerContainerState();
}

class _MainDialerContainerState extends State<MainDialerContainer> {
  static const MethodChannel _telecomChannel = MethodChannel(
    'com.example.telicall_voice_app/telecom',
  );
  final VoiceService _voiceService = VoiceService();

  int _currentTabIndex = 0;
  bool _isAiCallingMode = false;
  String _selectedStatusFilter = "PENDING";
  String _reportRange = "daily";

  String _dialedNumber = "";
  int? _activeLeadId;
  bool _isCallActive = false;
  bool _isDialingOut = false;

  // 📞 Call Status & Live Transcripts
  CallStatus _callStatus = CallStatus.idle;
  final List<Map<String, String>> _liveTranscripts = [];
  Timer? _callTimer;
  int _callDurationSeconds = 0;

  List<Contact> _deviceContacts = [];
  List<Contact> _filteredContacts = [];
  bool _isLoadingContacts = false;
  bool _hasContactsPermission = false;
  final TextEditingController _searchController = TextEditingController();

  final List<CallLogModel> _recentCallsList = [];
  List<ContactQueueItem> _aiCallQueue = [];
  bool _isLoadingQueue = false;

  bool _isAutoDialing = false;
  Timer? _autoDialTimer;

  Map<String, dynamic> _analyticsData = {
    'total_called': 0,
    'total_pending': 0,
    'total_followup': 0,
    'most_asked_questions': [],
  };

  static const String baseUrl = "http://172.26.85.248:8000";

  @override
  void initState() {
    super.initState();

    // 📡 Listen for Native MethodChannel Callbacks from Kotlin
    _setupNativeTelecomListener();

    // 🤖 AI Speech Output Tokens
    _voiceService.onTokenReceived = (token) {
      if (mounted && _isAiCallingMode) {
        setState(() {
          if (_liveTranscripts.isEmpty ||
              _liveTranscripts.last['sender'] != 'AI') {
            _liveTranscripts.add({'sender': 'AI', 'text': token});
          } else {
            _liveTranscripts.last['text'] =
                (_liveTranscripts.last['text'] ?? '') + token;
          }
        });
      }
    };

    // 👤 Customer Speech-to-Text Transcript Feed
    _voiceService.onTranscriptReceived = (sender, text) {
      if (mounted && _isAiCallingMode) {
        setState(() {
          _liveTranscripts.add({'sender': sender, 'text': text});
          if (_callStatus == CallStatus.ringing ||
              _callStatus == CallStatus.dialing) {
            _callStatus = CallStatus.inCall;
            _startCallTimer();
          }
        });
      }
    };

    // 🔌 Connection State Callback
    _voiceService.onStateChanged = (isConnected) {
      if (mounted && !isConnected && _isCallActive) {
        _handleCallEndedState();
      }
    };

    _requestDefaultDialerStatus();
    _loadDeviceContacts();
    _fetchAiCallQueue();
    _fetchAnalyticsReports();
    _searchController.addListener(_filterContactsList);
  }

  void _setupNativeTelecomListener() {
    _telecomChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCallAnswered':
          debugPrint(
            "✅ [FLUTTER] Native call answered! Sending call_answered to backend...",
          );
          if (_isCallActive && _isAiCallingMode) {
            _voiceService.notifyCallAnswered();
          }
          break;

        case 'onCallEnded':
          debugPrint("🔌 [FLUTTER] Native call ended!");
          _handleCallEndedState();
          break;
      }
    });
  }

  Future<void> _requestDefaultDialerStatus() async {
    try {
      await _telecomChannel.invokeMethod('requestDefaultDialer');
    } catch (e) {
      debugPrint("❌ Failed to request default dialer status: $e");
    }
  }

  void _startCallTimer() {
    _callDurationSeconds = 0;
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _callDurationSeconds++);
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$mins:$secs";
  }

  void _handleCallEndedState() {
    _stopCallTimer();
    if (mounted) {
      setState(() {
        _callStatus = CallStatus.ended;
      });
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isCallActive = false;
          _isDialingOut = false;
          _callStatus = CallStatus.idle;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _callTimer?.cancel();
    _autoDialTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDeviceContacts() async {
    if (!mounted) return;
    setState(() => _isLoadingContacts = true);

    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (status == PermissionStatus.granted) {
        List<Contact> contacts = await FlutterContacts.getAll(
          properties: {ContactProperty.name, ContactProperty.phone},
        );

        if (mounted) {
          setState(() {
            _deviceContacts = contacts;
            _filteredContacts = contacts;
            _hasContactsPermission = true;
            _isLoadingContacts = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasContactsPermission = false;
            _isLoadingContacts = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingContacts = false);
    }
  }

  void _toggleAutoDialer() {
    if (_isAutoDialing) {
      _stopAutoDialer();
    } else {
      if (_aiCallQueue.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ No pending contacts to auto-dial!")),
        );
        return;
      }
      setState(() {
        _isAutoDialing = true;
      });
      _dialNextInQueue();
    }
  }

  void _stopAutoDialer() {
    _autoDialTimer?.cancel();
    if (mounted) {
      setState(() => _isAutoDialing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("⏹️ Auto-Dialer Paused.")));
    }
  }

  void _dialNextInQueue() {
    if (!_isAutoDialing || !mounted) return;

    final pendingItems = _aiCallQueue
        .where((item) => item.status == "PENDING")
        .toList();

    if (pendingItems.isEmpty) {
      _stopAutoDialer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🎉 All pending leads called successfully!"),
        ),
      );
      return;
    }

    final currentLead = pendingItems.first;

    _executeCall(
      currentLead.phoneNumber,
      leadId: currentLead.id,
      contactName: currentLead.name,
      details: currentLead.details,
    );
  }

  void _filterContactsList() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredContacts = _deviceContacts.where((contact) {
        final String name = (contact.displayName ?? '').toLowerCase();
        final String phones = contact.phones
            .map((p) => p.number.replaceAll(RegExp(r'\s+'), ''))
            .join();
        return name.contains(query) || phones.contains(query);
      }).toList();
    });
  }

  Future<void> _fetchAiCallQueue([String? statusFilter]) async {
    if (!mounted) return;
    setState(() => _isLoadingQueue = true);

    final String filter = statusFilter ?? _selectedStatusFilter;

    try {
      final url = "$baseUrl/api/call-queue/?status=$filter";
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _selectedStatusFilter = filter;
            _aiCallQueue = data
                .map((item) => ContactQueueItem.fromJson(item))
                .toList();
            _isLoadingQueue = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingQueue = false);
      }
    } catch (e) {
      debugPrint("❌ Error fetching queue ($filter): $e");
      if (mounted) setState(() => _isLoadingQueue = false);
    }
  }

  Future<void> _fetchAnalyticsReports() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/reports/?range=$_reportRange"),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _analyticsData = jsonDecode(response.body);
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Error fetching analytics: $e");
    }
  }

  Future<void> _addNewLead(String name, String phone, String details) async {
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
        _fetchAiCallQueue("PENDING");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Lead Added to Queue!")),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error adding lead: $e");
    }
  }

  Future<void> _updateLeadStatus(int id, String status) async {
    try {
      await http.patch(
        Uri.parse("$baseUrl/api/call-queue/$id/update/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"status": status}),
      );
      _fetchAiCallQueue(_selectedStatusFilter);
      _fetchAnalyticsReports();
    } catch (e) {
      debugPrint("❌ Error updating status: $e");
    }
  }

  Future<void> _downloadReportCSV() async {
    final Uri url = Uri.parse("$baseUrl/api/reports/export/");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _executeCall(
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

      if (permissions[Permission.phone]?.isGranted != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Phone permission required.")),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint("⚠️ Permission warning: $e");
    }

    setState(() {
      _dialedNumber = cleanNumber;
      _activeLeadId = leadId;
      _isCallActive = true;
      _isDialingOut = true;
      _callStatus = CallStatus.dialing;
      _liveTranscripts.clear();
    });

    _recentCallsList.insert(
      0,
      CallLogModel(
        name: contactName ?? cleanNumber,
        phoneNumber: cleanNumber,
        time: "Just now",
        callType: "Outgoing",
      ),
    );

    String backendHost = "192.168.1.9:8000";
    try {
      final Uri parsedUri = Uri.parse(baseUrl);
      if (parsedUri.authority.isNotEmpty) backendHost = parsedUri.authority;
    } catch (_) {}

    try {
      await _telecomChannel.invokeMethod<bool>('makeNativeInternalCall', {
        'phoneNumber': cleanNumber,
        'isAiMode': _isAiCallingMode,
      });

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && _callStatus == CallStatus.dialing) {
          setState(() => _callStatus = CallStatus.ringing);
        }
      });

      if (_isAiCallingMode) {
        Future.delayed(const Duration(seconds: 3), () async {
          if (_isCallActive) {
            AudioStreamService().startAudioStreaming();
            _voiceService.connectToBackend(
              backendHost,
              cleanNumber,
              details: details ?? "",
            );
            _voiceService.syncHardwareCallState("OFFHOOK");

            await _telecomChannel.invokeMethod('setAudioMode', {
              'isAiMode': true,
            });

            if (mounted) {
              setState(() {
                _callStatus = CallStatus.inCall;
                _startCallTimer();
              });
            }
          }
        });
      } else {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _isCallActive) {
            setState(() {
              _callStatus = CallStatus.inCall;
              _startCallTimer();
            });
          }
        });
      }
    } catch (e) {
      _endCallSession(isUserAction: true);
      return;
    }

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isDialingOut = false);
    });
  }
  // Future<void> _executeCall(
  //   String number, {
  //   int? leadId,
  //   String? contactName,
  //   String? details,
  // }) async {
  //   if (number.trim().isEmpty) return;

  //   final String cleanNumber = number.replaceAll(RegExp(r'[^\d+]'), '');

  //   try {
  //     final Map<Permission, PermissionStatus> permissions = await [
  //       Permission.phone,
  //       Permission.microphone,
  //     ].request();

  //     if (permissions[Permission.phone]?.isGranted != true) {
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text("Phone permission required.")),
  //         );
  //       }
  //       return;
  //     }
  //   } catch (e) {
  //     debugPrint("⚠️ Permission warning: $e");
  //   }

  //   // ------------------------------------------------------------------
  //   // 🧠 CHECK BACKEND READINESS IF AI MODE IS ENABLED
  //   // ------------------------------------------------------------------
  //   if (_isAiCallingMode) {
  //     // 1. Show Loading Dialog
  //     showDialog(
  //       context: context,
  //       barrierDismissible: false,
  //       builder: (context) => const AlertDialog(
  //         backgroundColor: Color(0xFF1E1E1E),
  //         content: Row(
  //           children: [
  //             CircularProgressIndicator(color: Colors.deepPurpleAccent),
  //             SizedBox(width: 20),
  //             Expanded(
  //               child: Text(
  //                 "Initializing Neural AI Engine...\nPlease wait.",
  //                 style: TextStyle(color: Colors.white),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     );

  //     bool isReady = false;
  //     int retries = 0;
  //     const int maxRetries = 10; // Wait up to 20 seconds max

  //     // 2. Poll the /api/status/ endpoint
  //     while (!isReady && retries < maxRetries) {
  //       isReady = await _checkBackendReadiness(baseUrl);
  //       if (!isReady) {
  //         retries++;
  //         await Future.delayed(const Duration(seconds: 2));
  //       }
  //     }

  //     // Close loading dialog safely
  //     if (mounted) {
  //       Navigator.of(context, rootNavigator: true).pop();
  //     }

  //     if (!isReady) {
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(
  //             content: Text(
  //               "⚠️ Server timeout: AI engine is taking too long to load.",
  //             ),
  //             backgroundColor: Colors.redAccent,
  //           ),
  //         );
  //       }
  //       return; // Abort call placement
  //     }
  //   }

  //   // ------------------------------------------------------------------
  //   // 🚀 PROCEED WITH CALL PLACEMENT (EXECUTE ONLY WHEN READY)
  //   // ------------------------------------------------------------------
  //   setState(() {
  //     _dialedNumber = cleanNumber;
  //     _activeLeadId = leadId;
  //     _isCallActive = true;
  //     _isDialingOut = true;
  //     _callStatus = CallStatus.dialing;
  //     _liveTranscripts.clear();
  //   });

  //   _recentCallsList.insert(
  //     0,
  //     CallLogModel(
  //       name: contactName ?? cleanNumber,
  //       phoneNumber: cleanNumber,
  //       time: "Just now",
  //       callType: "Outgoing",
  //     ),
  //   );

  //   String backendHost = "172.26.85.248:8000";
  //   try {
  //     final Uri parsedUri = Uri.parse(baseUrl);
  //     if (parsedUri.authority.isNotEmpty) backendHost = parsedUri.authority;
  //   } catch (_) {}

  //   try {
  //     await _telecomChannel.invokeMethod<bool>('makeNativeInternalCall', {
  //       'phoneNumber': cleanNumber,
  //       'isAiMode': _isAiCallingMode,
  //     });

  //     Future.delayed(const Duration(milliseconds: 1500), () {
  //       if (mounted && _callStatus == CallStatus.dialing) {
  //         setState(() => _callStatus = CallStatus.ringing);
  //       }
  //     });

  //     if (_isAiCallingMode) {
  //       Future.delayed(const Duration(seconds: 2), () async {
  //         if (_isCallActive) {
  //           AudioStreamService().startAudioStreaming();
  //           _voiceService.connectToBackend(
  //             backendHost,
  //             cleanNumber,
  //             details: details ?? "",
  //           );
  //           _voiceService.syncHardwareCallState("OFFHOOK");

  //           await _telecomChannel.invokeMethod('setAudioMode', {
  //             'isAiMode': true,
  //           });

  //           if (mounted) {
  //             setState(() {
  //               _callStatus = CallStatus.inCall;
  //               _startCallTimer();
  //             });
  //           }
  //         }
  //       });
  //     } else {
  //       Future.delayed(const Duration(seconds: 2), () {
  //         if (mounted && _isCallActive) {
  //           setState(() {
  //             _callStatus = CallStatus.inCall;
  //             _startCallTimer();
  //           });
  //         }
  //       });
  //     }
  //   } catch (e) {
  //     _endCallSession(isUserAction: true);
  //     return;
  //   }

  //   Future.delayed(const Duration(seconds: 5), () {
  //     if (mounted) setState(() => _isDialingOut = false);
  //   });
  // }

  Future<bool> _checkBackendReadiness(String serverBaseUrl) async {
    try {
      final String statusUrl = "$serverBaseUrl/api/status/";
      debugPrint("🔍 Checking backend readiness at $statusUrl...");

      final response = await http
          .get(Uri.parse(statusUrl))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        debugPrint("✅ Backend AI engines are fully loaded!");
        return true;
      }
    } catch (e) {
      debugPrint("⏳ Backend is still initializing or unreachable: $e");
    }
    return false;
  }

  void _endCallSession({bool isUserAction = false}) async {
    if (_isDialingOut && _isCallActive && !isUserAction) return;

    try {
      await _telecomChannel.invokeMethod('disconnectCall');
    } catch (_) {}

    if (_isAiCallingMode) {
      _voiceService.syncHardwareCallState("IDLE");
      _voiceService.disconnectSession();
      AudioStreamService().stopAudioStreaming();
      if (_activeLeadId != null) {
        _updateLeadStatus(_activeLeadId!, "CALLED");
      }
    }

    _handleCallEndedState();

    if (_isAutoDialing) {
      _autoDialTimer = Timer(const Duration(seconds: 4), () {
        if (_isAutoDialing && !_isCallActive) {
          _dialNextInQueue();
        }
      });
    }
  }

  void _showAddLeadDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            "➕ Upload New AI Lead",
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Client Name"),
              ),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: "Phone Number"),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: detailsCtrl,
                decoration: const InputDecoration(
                  labelText: "Lead Details / Context",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
              ),
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
                  _addNewLead(nameCtrl.text, phoneCtrl.text, detailsCtrl.text);
                  Navigator.pop(context);
                }
              },
              child: const Text("Upload Lead"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> currentTabViews = _isAiCallingMode
        ? [_buildAiQueueTab(), _buildStatusTab(), _buildReportsTab()]
        : [_buildKeypadTab(), _buildRecentsTab(), _buildContactsTab()];

    final List<BottomNavigationBarItem> currentTabItems = _isAiCallingMode
        ? const [
            BottomNavigationBarItem(icon: Icon(Icons.queue), label: "AI Queue"),
            BottomNavigationBarItem(icon: Icon(Icons.rule), label: "Status"),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: "Reports",
            ),
          ]
        : const [
            BottomNavigationBarItem(icon: Icon(Icons.dialpad), label: "Keypad"),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: "Recents",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contacts),
              label: "Contacts",
            ),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isAiCallingMode ? "Telicall AI Portal" : "Telicall Direct Dialer",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (_isAiCallingMode && _currentTabIndex == 0)
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.greenAccent),
              onPressed: _showAddLeadDialog,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_isAiCallingMode) {
                _fetchAiCallQueue();
                _fetchAnalyticsReports();
              } else {
                _loadDeviceContacts();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_isCallActive) _buildModeToggleSwitch(),
            Expanded(
              child: _isCallActive
                  ? _buildInCallScreen()
                  : IndexedStack(
                      index: _currentTabIndex.clamp(
                        0,
                        currentTabViews.length - 1,
                      ),
                      children: currentTabViews,
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isCallActive
          ? null
          : BottomNavigationBar(
              currentIndex: _currentTabIndex.clamp(
                0,
                currentTabItems.length - 1,
              ),
              onTap: (index) {
                if (!_isCallActive) setState(() => _currentTabIndex = index);
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: const Color(0xFF1E1E1E),
              selectedItemColor: _isAiCallingMode
                  ? Colors.deepPurpleAccent
                  : Colors.blueAccent,
              unselectedItemColor: Colors.grey,
              items: currentTabItems,
            ),
    );
  }

  Widget _buildModeToggleSwitch() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_isCallActive) {
                  setState(() {
                    _isAiCallingMode = false;
                    _currentTabIndex = 0;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_isAiCallingMode
                      ? Colors.blueAccent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone, size: 18, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      "Direct Call",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_isCallActive) {
                  setState(() {
                    _isAiCallingMode = true;
                    _currentTabIndex = 0;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _isAiCallingMode
                      ? Colors.deepPurpleAccent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.psychology, size: 18, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      "AI Mode",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInCallScreen() {
    String statusLabel = "CALLING...";
    Color statusColor = Colors.orangeAccent;

    switch (_callStatus) {
      case CallStatus.dialing:
        statusLabel = "DIALING...";
        statusColor = Colors.orangeAccent;
        break;
      case CallStatus.ringing:
        statusLabel = "🔔 RINGING...";
        statusColor = Colors.yellowAccent;
        break;
      case CallStatus.inCall:
        statusLabel = "🟢 IN CALL (${_formatDuration(_callDurationSeconds)})";
        statusColor = Colors.greenAccent;
        break;
      case CallStatus.ended:
        statusLabel = "🔴 CALL ENDED";
        statusColor = Colors.redAccent;
        break;
      default:
        break;
    }

    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 10),
          CircleAvatar(
            radius: 42,
            backgroundColor: Colors.deepPurple.shade700,
            child: const Icon(Icons.person, size: 48, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            _dialedNumber.isEmpty ? "Unknown Number" : _dialedNumber,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: _liveTranscripts.isEmpty
                  ? const Center(
                      child: Text(
                        "🎧 Listening for customer voice...",
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _liveTranscripts.length,
                      itemBuilder: (context, index) {
                        final item = _liveTranscripts[index];
                        final isCustomer = item['sender'] == 'Customer';

                        return Align(
                          alignment: isCustomer
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isCustomer
                                  ? Colors.blueGrey.shade800
                                  : Colors.deepPurple.shade900,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isCustomer
                                      ? "👤 Customer"
                                      : "🤖 AI Assistant",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isCustomer
                                        ? Colors.lightBlueAccent
                                        : Colors.purpleAccent,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item['text'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
          FloatingActionButton.large(
            backgroundColor: Colors.redAccent,
            onPressed: () => _endCallSession(isUserAction: true),
            child: const Icon(Icons.call_end, size: 36, color: Colors.white),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildAiQueueTab() {
    final pendingCount = _aiCallQueue
        .where((item) => item.status == "PENDING")
        .length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _isAutoDialing
              ? Colors.green.shade900.withOpacity(0.5)
              : Colors.grey.shade900,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isAutoDialing
                          ? "🤖 AUTO-DIALER ACTIVE"
                          : "AI Auto-Dialer Ready",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isAutoDialing
                            ? Colors.greenAccent
                            : Colors.white,
                      ),
                    ),
                    Text(
                      "$pendingCount Pending Target(s)",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isAutoDialing
                      ? Colors.redAccent
                      : Colors.green,
                ),
                onPressed: _toggleAutoDialer,
                icon: Icon(_isAutoDialing ? Icons.pause : Icons.play_arrow),
                label: Text(_isAutoDialing ? "Pause" : "Start Auto-Dial"),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              minimumSize: const Size(double.infinity, 42),
            ),
            onPressed: _showAddLeadDialog,
            icon: const Icon(Icons.cloud_upload, size: 20),
            label: const Text("Upload List / Add Lead to Queue"),
          ),
        ),
        Expanded(
          child: _isLoadingQueue
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.deepPurpleAccent,
                  ),
                )
              : _aiCallQueue.isEmpty
              ? const Center(
                  child: Text(
                    "No leads pending in AI queue.",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _aiCallQueue.length,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemBuilder: (context, index) {
                    final item = _aiCallQueue[index];
                    return Card(
                      color: Colors.grey.shade900,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          child: Text(
                            item.name.isNotEmpty
                                ? item.name[0].toUpperCase()
                                : "?",
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "${item.phoneNumber}\nContext: ${item.details}",
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.call,
                            color: Colors.greenAccent,
                          ),
                          onPressed: () => _executeCall(
                            item.phoneNumber,
                            leadId: item.id,
                            contactName: item.name,
                            details: item.details,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatusTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "PENDING", label: Text("Pending")),
              ButtonSegment(value: "CALLED", label: Text("Called")),
              ButtonSegment(value: "FOLLOW_UP", label: Text("Follow Up")),
            ],
            selected: {_selectedStatusFilter},
            onSelectionChanged: (val) {
              setState(() => _selectedStatusFilter = val.first);
              _fetchAiCallQueue();
            },
          ),
        ),
        Expanded(
          child: _isLoadingQueue
              ? const Center(child: CircularProgressIndicator())
              : _aiCallQueue.isEmpty
              ? Center(
                  child: Text(
                    "No records for status: $_selectedStatusFilter",
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _aiCallQueue.length,
                  itemBuilder: (context, index) {
                    final item = _aiCallQueue[index];
                    return ListTile(
                      leading: Icon(
                        item.status == "CALLED"
                            ? Icons.check_circle
                            : item.status == "FOLLOW_UP"
                            ? Icons.schedule
                            : Icons.pending,
                        color: item.status == "CALLED"
                            ? Colors.green
                            : item.status == "FOLLOW_UP"
                            ? Colors.orange
                            : Colors.blue,
                      ),
                      title: Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text("${item.phoneNumber} • ${item.details}"),
                      trailing: PopupMenuButton<String>(
                        onSelected: (newStatus) =>
                            _updateLeadStatus(item.id, newStatus),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: "PENDING",
                            child: Text("Set Pending"),
                          ),
                          PopupMenuItem(
                            value: "CALLED",
                            child: Text("Set Called"),
                          ),
                          PopupMenuItem(
                            value: "FOLLOW_UP",
                            child: Text("Set Follow Up"),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReportsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DropdownButton<String>(
                value: _reportRange,
                items: const [
                  DropdownMenuItem(value: "daily", child: Text("Daily Report")),
                  DropdownMenuItem(
                    value: "weekly",
                    child: Text("Weekly Report"),
                  ),
                  DropdownMenuItem(
                    value: "monthly",
                    child: Text("Monthly Report"),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _reportRange = val);
                    _fetchAnalyticsReports();
                  }
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                ),
                onPressed: _downloadReportCSV,
                icon: const Icon(Icons.download, size: 18),
                label: const Text("Export CSV"),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatCard(
                "Calls Made",
                "${_analyticsData['total_called']}",
                Colors.green,
              ),
              _buildStatCard(
                "Pending",
                "${_analyticsData['total_pending']}",
                Colors.blue,
              ),
              _buildStatCard(
                "Follow Ups",
                "${_analyticsData['total_followup']}",
                Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            "🔥 Most Asked Questions by Leads:",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          ...(_analyticsData['most_asked_questions'] as List<dynamic>).map(
            (q) => Card(
              color: Colors.grey.shade900,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(
                  Icons.question_answer,
                  color: Colors.deepPurpleAccent,
                ),
                title: Text(
                  "$q",
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String count, Color color) {
    return Expanded(
      child: Card(
        color: Colors.grey.shade900,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(
                count,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadTab() {
    final List<List<String>> keys = [
      ["1", "2", "3"],
      ["4", "5", "6"],
      ["7", "8", "9"],
      ["*", "0", "#"],
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var row in keys)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) => _buildKeypadButton(key)).toList(),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 64),
            FloatingActionButton.large(
              backgroundColor: Colors.green,
              onPressed: () => _executeCall(_dialedNumber),
              child: const Icon(Icons.call, size: 36, color: Colors.white),
            ),
            IconButton(
              icon: const Icon(
                Icons.backspace_outlined,
                color: Colors.white54,
                size: 28,
              ),
              onPressed: () {
                if (_dialedNumber.isNotEmpty) {
                  setState(
                    () => _dialedNumber = _dialedNumber.substring(
                      0,
                      _dialedNumber.length - 1,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String label) {
    return InkWell(
      onTap: () {
        if (_dialedNumber.length < 15) {
          setState(() => _dialedNumber += label);
        }
      },
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 28, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildRecentsTab() {
    if (_recentCallsList.isEmpty) {
      return const Center(
        child: Text(
          "No recent calls yet",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _recentCallsList.length,
      itemBuilder: (context, index) {
        final log = _recentCallsList[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey.shade800,
            child: const Icon(Icons.call_made, color: Colors.greenAccent),
          ),
          title: Text(
            log.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            "${log.phoneNumber} • ${log.time}",
            style: const TextStyle(color: Colors.white54),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.call, color: Colors.green),
            onPressed: () =>
                _executeCall(log.phoneNumber, contactName: log.name),
          ),
        );
      },
    );
  }

  Widget _buildContactsTab() {
    if (_isLoadingContacts) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
      );
    }

    if (!_hasContactsPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Permission required to view phone contacts.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
              ),
              onPressed: _loadDeviceContacts,
              child: const Text("Grant Permission"),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Search contacts...",
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: Colors.grey.shade900,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredContacts.length,
            itemBuilder: (context, index) {
              final contact = _filteredContacts[index];
              final String name = (contact.displayName ?? '').isNotEmpty
                  ? contact.displayName!
                  : "Unknown Contact";
              final String phone = contact.phones.isNotEmpty
                  ? contact.phones.first.number
                  : "No number";

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : "?",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  phone,
                  style: const TextStyle(color: Colors.white54),
                ),
                trailing: phone != "No number"
                    ? IconButton(
                        icon: const Icon(Icons.call, color: Colors.green),
                        onPressed: () => _executeCall(phone, contactName: name),
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
