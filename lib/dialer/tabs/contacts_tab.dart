import 'package:flutter/material.dart';
import '../dialer_controller.dart';

class ContactsTab extends StatelessWidget {
  final DialerController controller;

  const ContactsTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.isLoadingContacts) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
      );
    }

    if (!controller.hasContactsPermission) {
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
              onPressed: controller.loadDeviceContacts,
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
            controller: controller.searchController,
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
            itemCount: controller.filteredContacts.length,
            itemBuilder: (context, index) {
              final contact = controller.filteredContacts[index];
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
                        onPressed: () =>
                            controller.executeCall(phone, contactName: name),
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
