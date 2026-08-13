import 'package:flutter/material.dart';
import '../dialer_controller.dart';

class InCallOverlay extends StatelessWidget {
  final DialerController controller;

  const InCallOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    String statusLabel = "CALLING...";
    Color statusColor = Colors.orangeAccent;

    switch (controller.callStatus) {
      case CallStatus.dialing:
        statusLabel = "DIALING...";
        statusColor = Colors.orangeAccent;
        break;
      case CallStatus.ringing:
        statusLabel = "🔔 RINGING...";
        statusColor = Colors.yellowAccent;
        break;
      case CallStatus.inCall:
        statusLabel =
            "🟢 IN CALL (${controller.formatDuration(controller.callDurationSeconds)})";
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
            controller.dialedNumber.isEmpty
                ? "Unknown Number"
                : controller.dialedNumber,
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
              child: controller.liveTranscripts.isEmpty
                  ? const Center(
                      child: Text(
                        "🎧 Listening for customer voice...",
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: controller.liveTranscripts.length,
                      itemBuilder: (context, index) {
                        final item = controller.liveTranscripts[index];
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
            onPressed: () => controller.endCallSession(isUserAction: true),
            child: const Icon(Icons.call_end, size: 36, color: Colors.white),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
