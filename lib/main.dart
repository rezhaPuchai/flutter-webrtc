import 'package:flutter/material.dart';
import 'package:test_web_rtc/second/home_page.dart';

import 'join_room_screen.dart';

void main() {
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teleconference App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
      // home: const JoinRoomScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
