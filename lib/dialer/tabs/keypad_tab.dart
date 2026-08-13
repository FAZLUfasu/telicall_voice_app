import 'package:flutter/material.dart';
import '../dialer_controller.dart';

class KeypadTab extends StatelessWidget {
  final DialerController controller;

  const KeypadTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
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
              onPressed: () => controller.executeCall(controller.dialedNumber),
              child: const Icon(Icons.call, size: 36, color: Colors.white),
            ),
            IconButton(
              icon: const Icon(
                Icons.backspace_outlined,
                color: Colors.white54,
                size: 28,
              ),
              onPressed: controller.backspaceKeypadDigit,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String label) {
    return InkWell(
      onTap: () => controller.appendKeypadDigit(label),
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
}
