import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

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
    );
  }
}

class CallLogModel {
  final String name;
  final String phoneNumber;
  final String time;
  final String callType;

  CallLogModel({
    required this.name,
    required this.phoneNumber,
    required this.time,
    required this.callType,
  });
}

class ContactQueueItem {
  final int id;
  final String name;
  final String phoneNumber;
  final String details;
  final String status;
  final String? topQuestion;

  ContactQueueItem({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.details,
    required this.status,
    this.topQuestion,
  });

  factory ContactQueueItem.fromJson(Map<String, dynamic> json) {
    return ContactQueueItem(
      id: json['id'],
      name: json['name'],
      phoneNumber: json['phone_number'],
      details: json['details'] ?? 'No details provided',
      status: json['status'] ?? 'PENDING',
      topQuestion: json['top_question'],
    );
  }
}

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  Function(String)? onTokenReceived;

  bool get isConnected => _isConnected;

  void connectToBackend(
    String serverIp,
    String clientNumber, {
    String? details,
  }) {
    if (_isConnected && _channel != null) return;

    final String wsUrl = "ws://$serverIp:8000/ws/media-stream/";
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;

      _channel!.sink.add(
        jsonEncode({
          "client_phone_number": clientNumber,
          "lead_details": details ?? "",
        }),
      );

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['event'] == 'ai_token' && onTokenReceived != null) {
              onTokenReceived!(data['text']);
            }
          } catch (_) {
            if (onTokenReceived != null) onTokenReceived!(message);
          }
        },
        onError: (error) => _isConnected = false,
        onDone: () => _isConnected = false,
      );
    } catch (_) {
      _isConnected = false;
    }
  }

  void syncHardwareCallState(String state) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(
          jsonEncode({"event": "call_state_changed", "state": state}),
        );
      } catch (_) {}
    }
  }

  void disconnectSession() {
    if (!_isConnected) return;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
  }
}

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

  // Active call states
  String _dialedNumber = "";
  int? _activeLeadId;
  bool _isCallActive = false;
  bool _isDialingOut = false;
  String _activeCallStateText = "READY TO DIAL";
  String _aiSuggestionsOutputText = "Awaiting call initiation...";

  // Mobile Contacts List & Search
  List<Contact> _deviceContacts = [];
  List<Contact> _filteredContacts = [];
  bool _isLoadingContacts = false;
  bool _hasContactsPermission = false;
  final TextEditingController _searchController = TextEditingController();

  // Call Logs & AI Queue
  final List<CallLogModel> _recentCallsList = [];
  List<ContactQueueItem> _aiCallQueue = [];
  bool _isLoadingQueue = false;
  // 🤖 Auto-Dialer Loop Controllers
  bool _isAutoDialing = false;
  int _autoDialIndex = 0;
  Timer? _autoDialTimer;

  // Analytics
  Map<String, dynamic> _analyticsData = {
    'total_called': 0,
    'total_pending': 0,
    'total_followup': 0,
    'most_asked_questions': [],
  };

  @override
  void initState() {
    super.initState();
    _voiceService.onTokenReceived = (token) {
      if (mounted && _isAiCallingMode) {
        setState(() {
          if (_aiSuggestionsOutputText.startsWith("Awaiting")) {
            _aiSuggestionsOutputText = token;
          } else {
            _aiSuggestionsOutputText += token;
          }
        });
      }
    };

    _loadDeviceContacts();
    _fetchAiCallQueue();
    _fetchAnalyticsReports();
    _searchController.addListener(_filterContactsList);
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  // 🚀 START / TOGGLE AUTO-DIALER
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
        _autoDialIndex = 0;
      });
      _dialNextInQueue();
    }
  }

  void _stopAutoDialer() {
    _autoDialTimer?.cancel();
    if (mounted) {
      setState(() {
        _isAutoDialing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("⏹️ Auto-Dialer Paused.")));
    }
  }

  void _dialNextInQueue() {
    if (!_isAutoDialing || !mounted) return;

    // Find remaining pending items
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

    // Get current lead
    final currentLead = pendingItems.first;

    // Execute Call
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

  Future<void> _fetchAiCallQueue() async {
    setState(() => _isLoadingQueue = true);
    try {
      // Force status=PENDING for the AI Queue tab
      final url = "http://192.168.1.7:8000/api/call-queue/?status=PENDING";
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _aiCallQueue = data
              .map((item) => ContactQueueItem.fromJson(item))
              .toList();
          _isLoadingQueue = false;
        });
      } else {
        setState(() => _isLoadingQueue = false);
      }
    } catch (e) {
      print("❌ Error fetching queue: $e");
      setState(() => _isLoadingQueue = false);
    }
  }

  Future<void> _fetchAnalyticsReports() async {
    try {
      final response = await http.get(
        Uri.parse("http://192.168.1.7:8000/api/reports/?range=$_reportRange"),
      );
      if (response.statusCode == 200) {
        setState(() {
          _analyticsData = jsonDecode(response.body);
        });
      }
    } catch (_) {}
  }

  Future<void> _addNewLead(String name, String phone, String details) async {
    try {
      final response = await http.post(
        Uri.parse("http://192.168.1.7:8000/api/call-queue/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "phone_number": phone,
          "details": details,
        }),
      );
      if (response.statusCode == 201) {
        _fetchAiCallQueue();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Lead Added to Queue!")),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _updateLeadStatus(int id, String status) async {
    try {
      await http.patch(
        Uri.parse("http://192.168.1.7:8000/api/call-queue/$id/update/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"status": status}),
      );
      _fetchAiCallQueue();
      _fetchAnalyticsReports();
    } catch (_) {}
  }

  Future<void> _downloadReportCSV() async {
    final Uri url = Uri.parse("http://192.168.1.7:8000/api/reports/export/");
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

    setState(() {
      _dialedNumber = cleanNumber;
      _activeLeadId = leadId;
      _isCallActive = true;
      _isDialingOut = true;
      _activeCallStateText = _isAiCallingMode
          ? "🤖 AI CALLING: ${contactName ?? cleanNumber}"
          : "📞 DIRECT CALL: $cleanNumber";
      _aiSuggestionsOutputText = _isAiCallingMode
          ? "Target Details: ${details ?? 'Direct Contact'}\n\nAwaiting speech..."
          : "Direct Calling Mode Active";
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

    if (_isAiCallingMode) {
      _voiceService.connectToBackend(
        "192.168.1.7",
        cleanNumber,
        details: details,
      );
      _voiceService.syncHardwareCallState("OFFHOOK");
    }

    try {
      await _telecomChannel.invokeMethod('makeNativeInternalCall', {
        'phoneNumber': cleanNumber,
      });
    } catch (_) {
      _endCallSession(isUserAction: true);
      return;
    }

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isDialingOut = false);
    });
  }

  // void _endCallSession({bool isUserAction = false}) async {
  //   if (_isDialingOut && _isCallActive && !isUserAction) return;

  //   try {
  //     await _telecomChannel.invokeMethod('disconnectCall');
  //   } catch (_) {}

  //   if (_isAiCallingMode) {
  //     _voiceService.syncHardwareCallState("IDLE");
  //     _voiceService.disconnectSession();
  //     if (_activeLeadId != null) {
  //       _showPostCallStatusModal(_activeLeadId!);
  //     }
  //   }

  //   setState(() {
  //     _isCallActive = false;
  //     _isDialingOut = false;
  //     _activeCallStateText = "CALL ENDED";
  //   });
  // }
  void _endCallSession({bool isUserAction = false}) async {
    if (_isDialingOut && _isCallActive && !isUserAction) return;

    try {
      await _telecomChannel.invokeMethod('disconnectCall');
    } catch (_) {}

    if (_isAiCallingMode) {
      _voiceService.syncHardwareCallState("IDLE");
      _voiceService.disconnectSession();

      // Automatically mark lead as CALLED in backend during Auto-Dial mode
      if (_activeLeadId != null) {
        _updateLeadStatus(_activeLeadId!, "CALLED");
      }
    }

    setState(() {
      _isCallActive = false;
      _isDialingOut = false;
      _activeCallStateText = "CALL ENDED";
    });

    // 🔁 IF AUTO-DIALER IS ACTIVE, SCHEDULE NEXT CALL AFTER 4 SECONDS
    if (_isAutoDialing) {
      _autoDialTimer = Timer(const Duration(seconds: 4), () {
        if (_isAutoDialing && !_isCallActive) {
          _dialNextInQueue();
        }
      });
    }
  }

  void _showPostCallStatusModal(int leadId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Update Call Status",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    onPressed: () {
                      _updateLeadStatus(leadId, "CALLED");
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check),
                    label: const Text("Mark Called"),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    onPressed: () {
                      _updateLeadStatus(leadId, "FOLLOW_UP");
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.schedule),
                    label: const Text("Follow Up"),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
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
              tooltip: "Upload Lead",
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
            _buildModeToggleSwitch(),
            if (_isCallActive || _dialedNumber.isNotEmpty)
              _buildCallHeaderDisplay(),
            Expanded(
              child: _isCallActive
                  ? _buildActiveCallControls()
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex.clamp(0, currentTabItems.length - 1),
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
                if (!_isCallActive)
                  setState(() {
                    _isAiCallingMode = false;
                    _currentTabIndex = 0;
                  });
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
                if (!_isCallActive)
                  setState(() {
                    _isAiCallingMode = true;
                    _currentTabIndex = 0;
                  });
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

  Widget _buildCallHeaderDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Text(
            _activeCallStateText,
            style: TextStyle(
              color: _isCallActive ? Colors.greenAccent : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _dialedNumber.isEmpty ? "Select Target" : _dialedNumber,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          if (_isAiCallingMode || _isCallActive)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isAiCallingMode
                      ? Colors.deepPurpleAccent
                      : Colors.blueGrey,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isAiCallingMode ? Icons.psychology : Icons.phone_in_talk,
                    color: _isAiCallingMode
                        ? Colors.deepPurpleAccent
                        : Colors.blueAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _aiSuggestionsOutputText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // // 🤖 1. AI QUEUE TAB
  // Widget _buildAiQueueTab() {
  //   return Column(
  //     children: [
  //       Padding(
  //         padding: const EdgeInsets.all(12),
  //         child: ElevatedButton.icon(
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: Colors.deepPurple,
  //             minimumSize: const Size(double.infinity, 45),
  //           ),
  //           onPressed: _showAddLeadDialog,
  //           icon: const Icon(Icons.cloud_upload),
  //           label: const Text("Upload List / Add Lead to Queue"),
  //         ),
  //       ),
  //       Expanded(
  //         child: _isLoadingQueue
  //             ? const Center(
  //                 child: CircularProgressIndicator(
  //                   color: Colors.deepPurpleAccent,
  //                 ),
  //               )
  //             : _aiCallQueue.isEmpty
  //             ? const Center(
  //                 child: Text(
  //                   "No leads pending in AI queue.",
  //                   style: TextStyle(color: Colors.grey),
  //                 ),
  //               )
  //             : ListView.builder(
  //                 itemCount: _aiCallQueue.length,
  //                 padding: const EdgeInsets.symmetric(horizontal: 12),
  //                 itemBuilder: (context, index) {
  //                   final item = _aiCallQueue[index];
  //                   return Card(
  //                     color: Colors.grey.shade900,
  //                     margin: const EdgeInsets.only(bottom: 10),
  //                     child: ListTile(
  //                       leading: CircleAvatar(
  //                         backgroundColor: Colors.deepPurple,
  //                         child: Text(
  //                           item.name.isNotEmpty
  //                               ? item.name[0].toUpperCase()
  //                               : "?",
  //                           style: const TextStyle(color: Colors.white),
  //                         ),
  //                       ),
  //                       title: Text(
  //                         item.name,
  //                         style: const TextStyle(
  //                           fontWeight: FontWeight.bold,
  //                           color: Colors.white,
  //                         ),
  //                       ),
  //                       subtitle: Text(
  //                         "${item.phoneNumber}\nContext: ${item.details}",
  //                         style: const TextStyle(
  //                           color: Colors.white60,
  //                           fontSize: 12,
  //                         ),
  //                       ),
  //                       trailing: IconButton(
  //                         icon: const Icon(
  //                           Icons.call,
  //                           color: Colors.greenAccent,
  //                         ),
  //                         onPressed: () => _executeCall(
  //                           item.phoneNumber,
  //                           leadId: item.id,
  //                           contactName: item.name,
  //                           details: item.details,
  //                         ),
  //                       ),
  //                     ),
  //                   );
  //                 },
  //               ),
  //       ),
  //     ],
  //   );
  // }
  Widget _buildAiQueueTab() {
    final pendingCount = _aiCallQueue
        .where((item) => item.status == "PENDING")
        .length;

    return Column(
      children: [
        // 🚀 AUTO-DIALER CONTROL BANNER
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
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

  // 📋 2. STATUS TAB (PENDING / CALLED / FOLLOW UP)
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

  // 📊 3. REPORTS & ANALYTICS TAB
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

  // 1️⃣ KEYPAD TAB VIEW
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

  // 2️⃣ RECENTS TAB VIEW
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

  // 3️⃣ CONTACTS TAB VIEW
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

  Widget _buildActiveCallControls() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FloatingActionButton.large(
            backgroundColor: Colors.red,
            onPressed: () => _endCallSession(isUserAction: true),
            child: const Icon(Icons.call_end, size: 38, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            "Tap to Disconnect Call",
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
