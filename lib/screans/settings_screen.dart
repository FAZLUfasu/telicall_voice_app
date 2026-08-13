import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _enableVAD = true;
  bool _autoRecordChunks = true;
  bool _bargeInEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("App Settings"),
        backgroundColor: Colors.indigo,
        elevation: 2,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0, left: 4.0),
            child: Text(
              "Audio Pipeline Configuration",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.indigoAccent,
              ),
            ),
          ),
          Card(
            color: Colors.grey.shade900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text("Voice Activity Detection (VAD)"),
                  subtitle: const Text(
                    "Auto-split incoming audio upon silence",
                  ),
                  value: _enableVAD,
                  activeThumbColor: Colors.indigoAccent,
                  onChanged: (val) => setState(() => _enableVAD = val),
                ),
                const Divider(height: 1, color: Colors.white12),
                SwitchListTile(
                  title: const Text("Local Chunk Recording"),
                  subtitle: const Text(
                    "Save WAV chunks to device for debugging",
                  ),
                  value: _autoRecordChunks,
                  activeThumbColor: Colors.indigoAccent,
                  onChanged: (val) => setState(() => _autoRecordChunks = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0, left: 4.0),
            child: Text(
              "AI Conversation Rules",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.indigoAccent,
              ),
            ),
          ),
          Card(
            color: Colors.grey.shade900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              title: const Text("Customer Barge-In"),
              subtitle: const Text("Allow customer to interrupt AI speech"),
              value: _bargeInEnabled,
              activeThumbColor: Colors.indigoAccent,
              onChanged: (val) => setState(() => _bargeInEnabled = val),
            ),
          ),
        ],
      ),
    );
  }
}
