import 'package:flutter/material.dart';

class StepProgressBar extends StatelessWidget {
  final int currentStep;

  const StepProgressBar({super.key, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6B00);
    const gray = Colors.grey;

    List<String> steps = ['1', '2', '3'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(steps.length, (index) {
        bool isActive = currentStep >= index + 1;

        return Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isActive ? orange : gray.shade300,
                child: Text(
                  steps[index],
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.black54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                stepLabel(index),
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? orange : gray,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  String stepLabel(int index) {
    switch (index) {
      case 0:
        return 'Personal Details';
      case 1:
        return 'Vehicle Information';
      case 2:
        return 'Identity & Vehicle Verify';
      default:
        return '';
    }
  }
}
