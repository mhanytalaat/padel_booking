import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PadelCore")),
      body: const Center(
        child: Text(
          "Firebase Connected ✅",
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}
