import 'package:flutter/material.dart';
import '../dialer_controller.dart';

class AiQueueTab extends StatelessWidget {
  final DialerController controller;
  final VoidCallback onAddLead;

  const AiQueueTab({
    super.key,
    required this.controller,
    required this.onAddLead,
  });

  @override
  Widget build(BuildContext context) {
    final pendingCount = controller.aiCallQueue
        .where((item) => item.status == "PENDING")
        .length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: controller.isAutoDialing
              ? Colors.green.shade900.withValues(alpha: 0.5)
              : Colors.grey.shade900,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.isAutoDialing
                          ? "🤖 AUTO-DIALER ACTIVE"
                          : "AI Auto-Dialer Ready",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: controller.isAutoDialing
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
                  backgroundColor: controller.isAutoDialing
                      ? Colors.redAccent
                      : Colors.green,
                ),
                onPressed: controller.toggleAutoDialer,
                icon: Icon(
                  controller.isAutoDialing ? Icons.pause : Icons.play_arrow,
                ),
                label: Text(
                  controller.isAutoDialing ? "Pause" : "Start Auto-Dial",
                ),
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
            onPressed: onAddLead,
            icon: const Icon(Icons.cloud_upload, size: 20),
            label: const Text("Upload List / Add Lead to Queue"),
          ),
        ),
        Expanded(
          child: controller.isLoadingQueue
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.deepPurpleAccent,
                  ),
                )
              : controller.aiCallQueue.isEmpty
              ? const Center(
                  child: Text(
                    "No leads pending in AI queue.",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: controller.aiCallQueue.length,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemBuilder: (context, index) {
                    final item = controller.aiCallQueue[index];
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
                          onPressed: () => controller.executeCall(
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
}
