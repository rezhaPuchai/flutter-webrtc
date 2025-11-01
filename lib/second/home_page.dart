
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart';
import 'package:test_web_rtc/second/permission_service.dart';
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
                onPressed: () async {
                  // Pre-check cepat sebelum request
                  final bool hasPreflight = await PermissionService.checkEssentialPermissionsPreflight();

                  if (hasPreflight) {
                    // Jika sudah ada permission, langsung navigate dengan delay safety
                    await Future.delayed(const Duration(milliseconds: 300));
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => VideoCallScreen(roomId: _roomCtrl.text.trim()),
                    ));
                    return;
                  }

                  // Jika belum, request permissions
                  final result = await PermissionService.requestVideoCallPermissions(context);

                  if (result.essentialGranted) {
                    // Success - navigate ke VideoCallScreen
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => VideoCallScreen(roomId: _roomCtrl.text.trim()),
                    ));
                  } else {
                    // Failed - show error message
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result.error ?? 'Akses kamera dan mikrofon diperlukan untuk video call',
                        ),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.video_call),
                label: const Text('Join Video Call'),
              )
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