import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:test_web_rtc/learn-rtc/room_page.dart';
import 'package:uuid/uuid.dart';

class FormRoomPage extends StatefulWidget {
  const FormRoomPage({super.key});

  @override
  State<FormRoomPage> createState() => _FormRoomPageState();
}

class _FormRoomPageState extends State<FormRoomPage> {
  final TextEditingController _roomCtrl = TextEditingController(text: '8uw9s87s');
  final TextEditingController _nameCtrl = TextEditingController(text: 'user-${const Uuid().v4().substring(0, 6)}');

  late io.Socket socket;
  String? selfId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Learn RTC"),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _roomCtrl,
              decoration: const InputDecoration(labelText: 'Room ID (/room/{id})'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Display name (any string)'),
            ),
            const SizedBox(height: 30),
            SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RoomPage(roomId: _roomCtrl.text.trim(),),
                    ));
                  },
                  icon: const Icon(Icons.smartphone),
                  label: const Text('Join'),
                )
            ),
          ],
        ),
      ),
    );
  }
}
