import 'package:flutter/material.dart';

class ProfileManagementScreen extends StatelessWidget {
  const ProfileManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile Management"),
        backgroundColor: Colors.indigo,
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const CircleAvatar(
              radius: 45,
              backgroundColor: Colors.indigoAccent,
              child: Icon(Icons.person, size: 50, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text(
              "AI Sales Agent",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Active & Ready",
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 32),
            Card(
              color: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const ListTile(
                leading: Icon(Icons.badge, color: Colors.indigoAccent),
                title: Text("Agent Name"),
                subtitle: Text("Telicall AI Assistant"),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              color: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const ListTile(
                leading: Icon(Icons.phone, color: Colors.indigoAccent),
                title: Text("Default Caller ID"),
                subtitle: Text("System Default Dialing Number"),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              color: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const ListTile(
                leading: Icon(Icons.language, color: Colors.indigoAccent),
                title: Text("Primary Language"),
                subtitle: Text("English (en-US)"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
