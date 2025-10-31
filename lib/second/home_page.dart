
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart';
import 'package:test_web_rtc/second/video_call_screen.dart';
import 'package:uuid/uuid.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}


class _HomePageState extends State<HomePage> {
  final TextEditingController _roomCtrl = TextEditingController(text: '8uw9s87s');
  final TextEditingController _nameCtrl = TextEditingController(text: 'user-${const Uuid().v4().substring(0, 6)}');

  late IO.Socket socket;
  String? selfId;
  final Map<String, dynamic> peers = {}; // mirip peersRef.current di JS


  Future<MediaStream> getUserMedia() async {
    final mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user', // kamera depan
        'width': { 'ideal': 1280 },
        'height': { 'ideal': 720 },
        'frameRate': { 'ideal': 30 },
      },
    };

    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    return stream;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Room')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => VideoCallScreen(roomId: _roomCtrl.text.trim()),
                  ));
                  // connect("https://signaling-websocket.payuung.com", "y3m9axjs", getUserMedia());
                  // Navigator.of(context).push(MaterialPageRoute(
                  //   builder: (_) => CallPage(roomId: _roomCtrl.text.trim(), displayName: _nameCtrl.text.trim()),
                  // ));
                },
                icon: const Icon(Icons.video_call_outlined),
                label: const Text('Join'),
              ),
            )
          ],
        ),
      ),
    );
  }


  void connect(String signalingUrl, String roomId, dynamic stream) {
    socket = IO.io(
      signalingUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect() // optional
          .build(),
    );

    socket.connect();

    // Saat tersambung
    socket.onConnect((_) {
      selfId = socket.id;
      print('Connected: $selfId');

      // Emit join dan session seperti di JS
      socket.emit('join', roomId);
      socket.emit('session', {
        'roomId': roomId,
        'data': {'type': 'query'},
      });
    });
  }

  void createPeer(String peerId, bool polite, dynamic stream) {
    // Implementasi mirip JS (buat RTCPeerConnection)
    print('Creating peer for $peerId (polite: $polite)');
    peers[peerId] = {'polite': polite, 'stream': stream};
    // TODO: tambahkan logika WebRTC (menggunakan flutter_webrtc)
  }

  void disconnect() {
    socket.disconnect();
  }

}