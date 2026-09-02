import 'package:flutter/material.dart';

import 'dialer_controller.dart';
import 'widgets/mode_toggle_switch.dart';
import 'widgets/in_call_overlay.dart';

import 'tabs/ai_queue_tab.dart';
import 'tabs/status_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/keypad_tab.dart';
import 'tabs/recents_tab.dart';
import 'tabs/contacts_tab.dart';

import '../screans/audio_inspector_screen.dart';
import '../screans/ai_response_inspector_screen.dart';
import '../screans/profile_management_screen.dart';
import '../screans/settings_screen.dart';

class MainDialerScreen extends StatefulWidget {
  const MainDialerScreen({super.key});

  @override
  State<MainDialerScreen> createState() => _MainDialerScreenState();
}

class _MainDialerScreenState extends State<MainDialerScreen> {
  late final DialerController _controller;

  @override
  void initState() {
    super.initState();

    _controller = DialerController();

    _controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);

    _controller.dispose();

    super.dispose();
  }

  // ============================================================
  // MENU SELECTION
  // ============================================================

  void _handleMenuSelection(String value) {
    switch (value) {
      // ========================================================
      // CUSTOMER AUDIO
      // ========================================================

      case 'audio_inspector':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AudioInspectorScreen()),
        );

        break;

      // ========================================================
      // AI RESPONSE AUDIO
      // ========================================================

      case 'ai_response_inspector':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiResponseInspectorScreen()),
        );

        break;

      // ========================================================
      // PROFILE
      // ========================================================

      case 'profile_management':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileManagementScreen()),
        );

        break;

      // ========================================================
      // SETTINGS
      // ========================================================

      case 'settings':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );

        break;
    }
  }

  // ============================================================
  // ADD LEAD
  // ============================================================

  void _showAddLeadDialog() {
    final nameCtrl = TextEditingController();

    final phoneCtrl = TextEditingController();

    final detailsCtrl = TextEditingController();

    showDialog(
      context: context,

      builder: (context) => AlertDialog(
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
                _controller.addNewLead(
                  nameCtrl.text,
                  phoneCtrl.text,
                  detailsCtrl.text,
                );

                Navigator.pop(context);
              }
            },

            child: const Text("Upload Lead"),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // ==========================================================
    // CURRENT TAB VIEWS
    // ==========================================================

    final currentTabViews = _controller.isAiCallingMode
        ? [
            AiQueueTab(controller: _controller, onAddLead: _showAddLeadDialog),

            StatusTab(controller: _controller),

            ReportsTab(controller: _controller),
          ]
        : [
            KeypadTab(controller: _controller),

            RecentsTab(controller: _controller),

            ContactsTab(controller: _controller),
          ];

    // ==========================================================
    // BOTTOM NAVIGATION ITEMS
    // ==========================================================

    final currentTabItems = _controller.isAiCallingMode
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
      // ==========================================================
      // APP BAR
      // ==========================================================
      appBar: AppBar(
        title: Text(
          _controller.isAiCallingMode
              ? "Telicall AI Portal"
              : "Telicall Direct Dialer",

          style: const TextStyle(fontWeight: FontWeight.bold),
        ),

        centerTitle: true,

        actions: [
          // ======================================================
          // ADD LEAD
          // ======================================================
          if (_controller.isAiCallingMode && _controller.currentTabIndex == 0)
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.greenAccent),

              onPressed: _showAddLeadDialog,
            ),

          // ======================================================
          // REFRESH
          // ======================================================
          IconButton(
            icon: const Icon(Icons.refresh),

            onPressed: () {
              if (_controller.isAiCallingMode) {
                _controller.fetchAiCallQueue();

                _controller.fetchAnalyticsReports();
              } else {
                _controller.loadDeviceContacts();
              }
            },
          ),

          // ======================================================
          // MORE MENU
          // ======================================================
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),

            onSelected: _handleMenuSelection,

            itemBuilder: (context) => const [
              // ==================================================
              // CUSTOMER AUDIO
              // ==================================================
              PopupMenuItem(
                value: 'audio_inspector',

                child: ListTile(
                  leading: Icon(Icons.graphic_eq, color: Colors.indigoAccent),

                  title: Text('Customer Audio'),

                  subtitle: Text('Recorded customer call audio'),
                ),
              ),

              // ==================================================
              // AI RESPONSE AUDIO
              // ==================================================
              PopupMenuItem(
                value: 'ai_response_inspector',

                child: ListTile(
                  leading: Icon(
                    Icons.smart_toy_outlined,
                    color: Colors.blueAccent,
                  ),

                  title: Text('AI Response Audio'),

                  subtitle: Text('Audio responses sent by AI'),
                ),
              ),

              // ==================================================
              // PROFILE MANAGEMENT
              // ==================================================
              PopupMenuItem(
                value: 'profile_management',

                child: ListTile(
                  leading: Icon(Icons.person, color: Colors.indigoAccent),

                  title: Text('Profile Management'),
                ),
              ),

              // ==================================================
              // SETTINGS
              // ==================================================
              PopupMenuItem(
                value: 'settings',

                child: ListTile(
                  leading: Icon(Icons.settings, color: Colors.indigoAccent),

                  title: Text('Settings'),
                ),
              ),
            ],
          ),
        ],
      ),

      // ==========================================================
      // BODY
      // ==========================================================
      body: SafeArea(
        child: Column(
          children: [
            // ====================================================
            // AI / DIRECT MODE SWITCH
            // ====================================================
            if (!_controller.isCallActive)
              ModeToggleSwitch(
                isAiMode: _controller.isAiCallingMode,

                onToggle: _controller.toggleAiMode,
              ),

            // ====================================================
            // CONTENT
            // ====================================================
            Expanded(
              child: _controller.isCallActive
                  ? InCallOverlay(controller: _controller)
                  : IndexedStack(
                      index: _controller.currentTabIndex.clamp(
                        0,
                        currentTabViews.length - 1,
                      ),

                      children: currentTabViews,
                    ),
            ),
          ],
        ),
      ),

      // ==========================================================
      // BOTTOM NAVIGATION
      // ==========================================================
      bottomNavigationBar: _controller.isCallActive
          ? null
          : BottomNavigationBar(
              currentIndex: _controller.currentTabIndex.clamp(
                0,
                currentTabItems.length - 1,
              ),

              onTap: _controller.setTabIndex,

              type: BottomNavigationBarType.fixed,

              backgroundColor: const Color(0xFF1E1E1E),

              selectedItemColor: _controller.isAiCallingMode
                  ? Colors.deepPurpleAccent
                  : Colors.blueAccent,

              unselectedItemColor: Colors.grey,

              items: currentTabItems,
            ),
    );
  }
}
