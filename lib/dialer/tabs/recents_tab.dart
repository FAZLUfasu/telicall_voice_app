import 'package:flutter/material.dart';
import '../dialer_controller.dart';

class RecentsTab extends StatelessWidget {
  final DialerController controller;

  const RecentsTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.recentCallsList.isEmpty) {
      return const Center(
        child: Text(
          "No recent calls yet",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: controller.recentCallsList.length,
      itemBuilder: (context, index) {
        final log = controller.recentCallsList[index];
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
                controller.executeCall(log.phoneNumber, contactName: log.name),
          ),
        );
      },
    );
  }
}
