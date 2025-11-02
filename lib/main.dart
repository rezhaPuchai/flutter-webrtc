import 'package:flutter/material.dart';
import 'package:test_web_rtc/learn-rtc/form_room_page.dart';
import 'package:test_web_rtc/second/home_page.dart';

void main() {
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teleconference App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MenuPage(),
      // home: const JoinRoomScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 30),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const HomePage(),
                  ));
                },
                icon: const Icon(Icons.smartphone),
                label: const Text('Home'),
              )
          ),
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FormRoomPage(),
                  ));
                },
                icon: const Icon(Icons.smartphone),
                label: const Text('Learn RTC'),
              )
          ),
        ],
      ),
    );
  }
}

