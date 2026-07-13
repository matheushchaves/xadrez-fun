import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/board/board_screen.dart';

void main() {
  runApp(const ProviderScope(child: XadrezFunApp()));
}

class XadrezFunApp extends StatelessWidget {
  const XadrezFunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xadrez Fun',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      home: const BoardScreen(),
    );
  }
}
