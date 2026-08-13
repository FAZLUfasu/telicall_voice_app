import 'package:flutter/material.dart';
import '../dialer_controller.dart';

class ReportsTab extends StatelessWidget {
  final DialerController controller;

  const ReportsTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DropdownButton<String>(
                value: controller.reportRange,
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
                    controller.reportRange = val;
                    controller.fetchAnalyticsReports();
                  }
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                ),
                onPressed: controller.downloadReportCSV,
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
                "${controller.analyticsData['total_called']}",
                Colors.green,
              ),
              _buildStatCard(
                "Pending",
                "${controller.analyticsData['total_pending']}",
                Colors.blue,
              ),
              _buildStatCard(
                "Follow Ups",
                "${controller.analyticsData['total_followup']}",
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
          ...((controller.analyticsData['most_asked_questions'] ?? [])
                  as List<dynamic>)
              .map(
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
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
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
}
