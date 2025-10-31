import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:test_web_rtc/signaling_model.dart';

class SignalingService {
  /*static const String _baseUrl = 'https://beta-teleconference.payuung.com';
  late IO.Socket _socket;
  String? _roomId;
  String? _userId;

  // Callbacks
  Function(RTCVideoRenderer)? onAddRemoteStream;
  Function(String)? onRemoveRemoteStream;
  Function(dynamic)? onIceCandidate;
  Function(String)? onRoomJoined;
  Function(String)? onError;

  Future<void> initialize() async {
    _userId = DateTime.now().millisecondsSinceEpoch.toString();

    _socket = IO.io(
      _baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    _socket.onConnect((_) {
      print('Connected to signaling server');
    });

    _socket.onDisconnect((_) {
      print('Disconnected from signaling server');
    });

    _socket.on('message', (data) {
      _handleSignalingMessage(data);
    });

    _socket.on('error', (error) {
      onError?.call(error.toString());
    });
  }

  void _handleSignalingMessage(dynamic data) {
    try {
      final message = data is Map<String, dynamic>
          ? SignalingMessage.fromJson(data)
          : SignalingMessage.fromJson(Map<String, dynamic>.from(data));

      switch (message.type) {
        case 'offer':
          onIceCandidate?.call(message.data);
          break;
        case 'answer':
          onIceCandidate?.call(message.data);
          break;
        case 'ice-candidate':
          onIceCandidate?.call(message.data);
          break;
        case 'user-joined':
          print('User joined: ${message.data}');
          break;
        case 'user-left':
          onRemoveRemoteStream?.call(message.data['userId']);
          break;
        case 'room-joined':
          onRoomJoined?.call(message.data['roomId']);
          break;
      }
    } catch (e) {
      print('Error handling signaling message: $e');
    }
  }

  Future<bool> joinRoom(String roomId) async {
    try {
      _roomId = roomId;

      _socket.emit('join-room', {
        'roomId': roomId,
        'userId': _userId,
      });

      return true;
    } catch (e) {
      onError?.call('Failed to join room: $e');
      return false;
    }
  }

  void sendOffer(RTCSessionDescription offer) {
    _socket.emit('message', {
      'type': 'offer',
      'data': offer.toMap(),
      'roomId': _roomId,
      'userId': _userId,
    });
  }

  void sendAnswer(RTCSessionDescription answer) {
    _socket.emit('message', {
      'type': 'answer',
      'data': answer.toMap(),
      'roomId': _roomId,
      'userId': _userId,
    });
  }

  void sendIceCandidate(RTCIceCandidate candidate) {
    _socket.emit('message', {
      'type': 'ice-candidate',
      'data': candidate.toMap(),
      'roomId': _roomId,
      'userId': _userId,
    });
  }

  void leaveRoom() {
    if (_roomId != null && _userId != null) {
      _socket.emit('leave-room', {
        'roomId': _roomId,
        'userId': _userId,
      });
    }
    _socket.disconnect();
  }

  void dispose() {
    leaveRoom();
  }*/
}