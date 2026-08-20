import 'package:flutter/material.dart';
import '../dialer_controller.dart';

class StatusTab extends StatelessWidget {
  final DialerController controller;

  const StatusTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          children: [
            _buildStatusSelector(context),
            const SizedBox(height: 4),
            Expanded(child: _buildQueueList(context)),
          ],
        );
      },
    );
  }

  // ============================================================
  // STATUS BUTTONS
  // ============================================================

  Widget _buildStatusSelector(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: "PENDING",
              label: Text("Pending"),
              icon: Icon(Icons.pending_actions),
            ),
            ButtonSegment<String>(
              value: "CALLED",
              label: Text("Called"),
              icon: Icon(Icons.check_circle_outline),
            ),
            ButtonSegment<String>(
              value: "FOLLOW_UP",
              label: Text("Follow Up"),
              icon: Icon(Icons.schedule),
            ),
          ],
          selected: {controller.selectedStatusFilter},
          onSelectionChanged: (Set<String> values) {
            if (values.isEmpty) return;

            final newStatus = values.first;

            controller.fetchAiCallQueue(newStatus);
          },
        ),
      ),
    );
  }

  // ============================================================
  // QUEUE LIST
  // ============================================================

  Widget _buildQueueList(BuildContext context) {
    if (controller.isLoadingQueue) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.aiCallQueue.isEmpty) {
      return RefreshIndicator(
        onRefresh: () {
          return controller.fetchAiCallQueue(controller.selectedStatusFilter);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getEmptyIcon(), size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      "No ${_statusDisplayName()} leads",
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Pull down to refresh",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () {
        return controller.fetchAiCallQueue(controller.selectedStatusFilter);
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
        itemCount: controller.aiCallQueue.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final item = controller.aiCallQueue[index];

          return _buildLeadCard(context, item);
        },
      ),
    );
  }

  // ============================================================
  // LEAD CARD
  // ============================================================

  Widget _buildLeadCard(BuildContext context, dynamic item) {
    final status = item.status.toString().toUpperCase();

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // STATUS ICON
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _statusIcon(status),
                color: _statusColor(status),
                size: 25,
              ),
            ),

            const SizedBox(width: 12),

            // LEAD INFORMATION
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          item.phoneNumber,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (item.details.toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],

                  const SizedBox(height: 7),

                  _buildStatusChip(status),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // STATUS MENU
            PopupMenuButton<String>(
              tooltip: "Change status",
              icon: const Icon(Icons.more_vert),
              onSelected: (newStatus) async {
                await controller.updateLeadStatus(item.id, newStatus);
              },
              itemBuilder: (context) {
                return const [
                  PopupMenuItem<String>(
                    value: "PENDING",
                    child: Row(
                      children: [
                        Icon(Icons.pending_actions, color: Colors.blue),
                        SizedBox(width: 10),
                        Text("Set Pending"),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: "CALLED",
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 10),
                        Text("Set Called"),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: "FOLLOW_UP",
                    child: Row(
                      children: [
                        Icon(Icons.schedule, color: Colors.orange),
                        SizedBox(width: 10),
                        Text("Set Follow Up"),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STATUS CHIP
  // ============================================================

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusDisplayName(),
        style: TextStyle(
          color: _statusColor(status),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Color _statusColor(String status) {
    switch (status) {
      case "CALLED":
        return Colors.green;

      case "FOLLOW_UP":
        return Colors.orange;

      case "PENDING":
      default:
        return Colors.blue;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case "CALLED":
        return Icons.check_circle;

      case "FOLLOW_UP":
        return Icons.schedule;

      case "PENDING":
      default:
        return Icons.pending_actions;
    }
  }

  IconData _getEmptyIcon() {
    switch (controller.selectedStatusFilter) {
      case "CALLED":
        return Icons.check_circle_outline;

      case "FOLLOW_UP":
        return Icons.schedule;

      case "PENDING":
      default:
        return Icons.pending_actions;
    }
  }

  String _statusDisplayName() {
    switch (controller.selectedStatusFilter) {
      case "CALLED":
        return "Called";

      case "FOLLOW_UP":
        return "Follow Up";

      case "PENDING":
      default:
        return "Pending";
    }
  }
}
