import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;


class WebRTCManager {
  late io.Socket socket;
  String? selfId;
  String? roomId;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final List<RTCVideoRenderer> _remoteStreams = [];

  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _isProcessing = false;
  String _currentCamera = 'user';
  bool _isDisposed = false;

  // Callbacks untuk UI
  Function(MediaStream)? onLocalStream;
  Function(String peerId, MediaStream)? onRemoteStream;
  Function(String peerId)? onPeerDisconnected;
  Function(String)? onError;
  Function()? onConnected;

  WebRTCManager();

  // Initialize WebRTC dan koneksi signaling
  Future<void> connect(String signalingUrl, String roomId) async {
    if (_isDisposed) return;

    this.roomId = roomId;

    try {
      // Dapatkan media stream lokal terlebih dahulu
      await _getUserMedia();

      // Setup koneksi socket
      _setupSocketConnection(signalingUrl, roomId);

      // Initialize peer connection
      await _initializePeerConnection();

    } catch (e) {
      debugPrint('Error connecting: $e');
      _safeCallback(() => onError?.call('Failed to connect: $e'));
    }
  }

// Ganti method _setupSocketConnection dengan yang lebih detail
  void _setupSocketConnection(String signalingUrl, String roomId) {
    if (_isDisposed) return;

    debugPrint('🔄 Setting up socket connection to: $signalingUrl');

    socket = io.io(
      signalingUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();

    // Event handlers dengan logging detail
    socket.onConnect((_) {
      if (_isDisposed) return;
      selfId = socket.id;
      debugPrint('✅ SOCKET CONNECTED: $selfId to room: $roomId');

      // Join room
      debugPrint('📤 EMITTING join event: $roomId');
      socket.emit('join', roomId);

      debugPrint('📤 EMITTING session event');
      socket.emit('session', {
        'roomId': roomId,
        'data': {'type': 'query'},
      });

      _safeCallback(() => onConnected?.call());

      // TAMBAHKAN: Force create offer setelah delay
      debugPrint('🔄 Scheduling automatic offer creation...');
      Future.delayed(const Duration(seconds: 3), () {
        if (!_isDisposed && _peerConnection != null) {
          debugPrint('🚀 Creating automatic offer...');
          _createOffer();
        }
      });
    });

    socket.onDisconnect((_) {
      debugPrint('❌ SOCKET DISCONNECTED');
    });

    socket.onError((error) {
      debugPrint('❌ SOCKET ERROR: $error');
      _safeCallback(() => onError?.call('Socket error: $error'));
    });

    

    // TAMBAHKAN EVENT LISTENER UNTUK SEMUA EVENT
    socket.onAny((event, data) {
      debugPrint('📡 [SOCKET EVENT] $event: $data');
    });

    // WebRTC signaling events dengan logging - TAMBAHKAN EVENT YANG MISSING
    socket.on('offer', (data) {
      debugPrint('📨 RECEIVED OFFER: $data');
      _handleRemoteOffer(data);
    });

    socket.on('answer', (data) {
      debugPrint('📨 RECEIVED ANSWER: $data');
      _handleRemoteAnswer(data);
    });

    socket.on('ice-candidate', (data) {
      debugPrint('🧊 RECEIVED ICE CANDIDATE: $data');
      _handleRemoteIceCandidate(data);
    });

    // TAMBAHKAN UNTUK DEBUG ROOM MANAGEMENT
    socket.on('joined', (data) {
      debugPrint('🎯 [JOINED ROOM] $data');
    });

    socket.on('user-joined', (data) {
      debugPrint('🎯 [USER JOINED ROOM] $data');
      // Force create offer ketika user baru join
      Future.delayed(const Duration(seconds: 1), () {
        _createOffer();
      });
    });

    socket.on('user-left', (data) {
      debugPrint('👤 USER LEFT: $data');
      _handleUserLeft(data);
    });

    socket.on('room-users', (data) {
      debugPrint('🎯 [ROOM USERS] $data');
      if (data is List && data.isNotEmpty) {
        debugPrint('👥 Users in room: ${data.length}');
        // Buat offer untuk setiap user yang ada
        _createOffer();
      }
    });

    // TAMBAHKAN EVENT HANDLER UNTUK ROOM INFO
    socket.on('room-info', (data) {
      debugPrint('🏠 ROOM INFO: $data');
    });

    socket.on('all-users', (data) {
      debugPrint('👥 ALL USERS IN ROOM: $data');
      // Jika ada users lain, buat offer
      if (data is List && data.isNotEmpty) {
        debugPrint('🎯 Other users in room, creating offer...');
        _createOffer();
      }
    });

    socket.on('message', (data) {
      debugPrint('📝 MESSAGE: $data');
    });

    socket.on('error', (data) {
      debugPrint('❌ SERVER ERROR: $data');
    });
  }
/*  void _setupSocketConnection(String signalingUrl, String roomId) {
    if (_isDisposed) return;

    debugPrint('🔄 Setting up socket connection to: $signalingUrl');

    socket = IO.io(
      signalingUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();

    // Event handlers dengan logging detail
    // socket.onConnect((_) {
    //   if (_isDisposed) return;
    //   selfId = socket.id;
    //   debugPrint('✅ SOCKET CONNECTED: $selfId to room: $roomId');
    //
    //   // Join room - PASTIKAN event ini dikirim
    //   debugPrint('📤 EMITTING join event: $roomId');
    //   socket.emit('join', roomId);
    //
    //   debugPrint('📤 EMITTING session event');
    //   socket.emit('session', {
    //     'roomId': roomId,
    //     'data': {'type': 'query'},
    //   });
    //
    //   _safeCallback(() => onConnected?.call());
    // });
    socket.onConnect((_) {
      if (_isDisposed) return;
      selfId = socket.id;
      debugPrint('✅ SOCKET CONNECTED: $selfId to room: $roomId');

      // Join room
      socket.emit('join', roomId);
      socket.emit('session', {
        'roomId': roomId,
        'data': {'type': 'query'},
      });

      _safeCallback(() => onConnected?.call());

      // Force create offer setelah delay
      Future.delayed(Duration(seconds: 2), () {
        debugPrint('🔄 Force creating offer...');
        _createOffer();
      });
    });

    socket.onDisconnect((_) {
      debugPrint('❌ SOCKET DISCONNECTED');
    });

    socket.onError((error) {
      debugPrint('❌ SOCKET ERROR: $error');
      _safeCallback(() => onError?.call('Socket error: $error'));
    });

    // WebRTC signaling events dengan logging
    socket.on('offer', (data) {
      debugPrint('📨 RECEIVED OFFER: $data');
      _handleRemoteOffer(data);
    });

    socket.on('answer', (data) {
      debugPrint('📨 RECEIVED ANSWER: $data');
      _handleRemoteAnswer(data);
    });

    socket.on('ice-candidate', (data) {
      debugPrint('🧊 RECEIVED ICE CANDIDATE: $data');
      _handleRemoteIceCandidate(data);
    });

    socket.on('user-joined', (data) {
      debugPrint('👤 USER JOINED: $data');
      _handleUserJoined(data);
    });

    socket.on('user-left', (data) {
      debugPrint('👤 USER LEFT: $data');
      _handleUserLeft(data);
    });

    // Tambahkan event handler untuk debugging
    socket.on('message', (data) {
      debugPrint('📝 MESSAGE: $data');
    });

    socket.on('error', (data) {
      debugPrint('❌ SERVER ERROR: $data');
    });
  }*/

  Future<void> _initializePeerConnection() async {
    if (_isDisposed) return;

    try {
      debugPrint('🔗 Initializing peer connection...');

      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun3.l.google.com:19302'},
          {'urls': 'stun:stun4.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan', // Important for modern WebRTC
      };

      _peerConnection = await createPeerConnection(configuration);
      debugPrint('✅ Peer connection created');

      // Setup event handlers untuk peer connection
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (_isDisposed) return;
        debugPrint('🧊 LOCAL ICE CANDIDATE: ${candidate.candidate}');
        socket.emit('ice-candidate', {
          'to': roomId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }
        });
      };

      _peerConnection!.onAddStream = (MediaStream stream) {
        if (_isDisposed) return;
        debugPrint('🎬 ON ADD STREAM: ${stream.id} with ${stream.getTracks().length} tracks');
        _addRemoteStream(stream);
      };

      // Gunakan onTrack untuk modern WebRTC
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (_isDisposed) return;
        debugPrint('🎬 ON TRACK: ${event.track.kind} - ${event.track.id}');
        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          debugPrint('📹 TRACK STREAM: ${stream.id} with ${stream.getTracks().length} tracks');
          _addRemoteStream(stream);
        }
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('🔗 CONNECTION STATE: $state');
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint('🧊 ICE CONNECTION STATE: $state');
      };

      _peerConnection!.onSignalingState = (RTCSignalingState state) {
        debugPrint('📶 SIGNALING STATE: $state');
      };

      // Add local stream tracks ke peer connection
      if (_localStream != null) {
        debugPrint('➕ Adding local tracks to peer connection');
        _localStream!.getTracks().forEach((track) {
          debugPrint('   - Adding track: ${track.kind} - ${track.id}');
          _peerConnection!.addTrack(track, _localStream!);
        });
      }

      debugPrint('✅ Peer connection initialized successfully');

    } catch (e) {
      debugPrint('❌ Error initializing peer connection: $e');
      _safeCallback(() => onError?.call('Failed to initialize peer connection: $e'));
    }
  }

  Future<void> _getUserMedia() async {
    if (_isDisposed) return;

    final mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      debugPrint('Got local media stream with ${_localStream!.getTracks().length} tracks');

      // Panggil callback untuk update UI
      _safeCallback(() => onLocalStream?.call(_localStream!));
    } catch (e) {
      debugPrint('Error getting user media: $e');
      _safeCallback(() => onError?.call('Failed to access camera/microphone: $e'));
      rethrow;
    }
  }

  void _handleUserLeft(dynamic data) {
    if (_isDisposed) return;
    final peerId = data['userId'];
    debugPrint('User left: $peerId');

    // Cleanup remote peer
    _remoteRenderers.remove(peerId);

    _safeCallback(() => onPeerDisconnected?.call(peerId));
  }

  void _handleRemoteAnswer(dynamic data) async {
    if (_isDisposed) return;
    debugPrint('Received remote answer: $data');

    try {
      if (_peerConnection == null) return;

      final answer = data['answer'];
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
    } catch (e) {
      debugPrint('Error handling remote answer: $e');
    }
  }

  void _handleRemoteIceCandidate(dynamic data) async {
    if (_isDisposed) return;
    debugPrint('Received remote ICE candidate: $data');

    try {
      if (_peerConnection == null) return;

      final candidateData = data['candidate'];
      await _peerConnection!.addCandidate(RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      ));
    } catch (e) {
      debugPrint('Error handling remote ICE candidate: $e');
    }
  }

// Buat offer untuk memulai panggilan
/*  Future<void> _createOffer() async {
    if (_isDisposed || _peerConnection == null) {
      debugPrint('❌ Cannot create offer - peer connection not ready');
      return;
    }

    try {
      debugPrint('📤 CREATING OFFER...');

      // Check signaling state
      debugPrint('📶 Current signaling state: ${_peerConnection!.signalingState}');

      // Buat offer dengan constraints yang tepat
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });

      debugPrint('✅ OFFER CREATED: ${offer.type}');
      debugPrint('📝 SDP Length: ${offer.sdp?.length} chars');

      // Set local description
      await _peerConnection!.setLocalDescription(offer);
      debugPrint('✅ LOCAL DESCRIPTION SET - New state: ${_peerConnection!.signalingState}');

      // Kirim offer ke signaling server
      debugPrint('📤 SENDING OFFER to room: $roomId');
      socket.emit('offer', {
        'to': roomId, // atau 'broadcast' tergantung server
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
        'from': selfId, // tambahkan from field
        'roomId': roomId,
      });

      debugPrint('✅ Offer sent successfully');

    } catch (e) {
      debugPrint('❌ Error creating offer: $e');
      debugPrint('🚨 Full error details: $e');
      _safeCallback(() => onError?.call('Failed to start call: $e'));
    }
  }*/

  Future<void> _createOffer() async {
    if (_isDisposed || _peerConnection == null) return;

    try {
      debugPrint('📤 CREATING OFFER...');

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      debugPrint('✅ OFFER CREATED - Sending multiple formats...');

      // COBA BERBAGAI FORMAT UNTUK TESTING
      // Format 1: Standard format
      socket.emit('offer', {
        'to': roomId,
        'from': selfId,
        'offer': offer.toMap(),
      });

      // Format 2: Simple format
      socket.emit('offer', {
        'roomId': roomId,
        'userId': selfId,
        'sdp': offer.toMap(),
      });

      // Format 3: Broadcast format
      socket.emit('offer', {
        'target': 'all',
        'roomId': roomId,
        'sender': selfId,
        'offer': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
      });

      // Format 4: Direct message format
      socket.emit('message', {
        'type': 'offer',
        'roomId': roomId,
        'from': selfId,
        'data': offer.toMap(),
      });

      debugPrint('✅ All offer formats sent');

    } catch (e) {
      debugPrint('❌ Error creating offer: $e');
    }
  }


/*  Future<void> _createOffer() async {
    if (_isDisposed || _peerConnection == null) {
      debugPrint('❌ Cannot create offer - peer connection not ready');
      return;
    }

    try {
      debugPrint('📤 CREATING OFFER...');

      // Buat offer dengan constraints yang tepat
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });

      debugPrint('✅ OFFER CREATED: ${offer.type}');
      debugPrint('📝 SDP: ${offer.sdp?.substring(0, 100)}...');

      await _peerConnection!.setLocalDescription(offer);
      debugPrint('✅ LOCAL DESCRIPTION SET');

      // Kirim offer ke signaling server
      debugPrint('📤 SENDING OFFER to room: $roomId');
      socket.emit('offer', {
        'to': roomId,
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        }
      });

      debugPrint('✅ Offer sent successfully');
    } catch (e) {
      debugPrint('❌ Error creating offer: $e');
      _safeCallback(() => onError?.call('Failed to start call: $e'));
    }
  }*/

  void _handleUserJoined(dynamic data) {
    if (_isDisposed) return;
    final userId = data['userId'];
    debugPrint('👤 USER JOINED - Creating offer for: $userId');

    // Tunggu sebentar sebelum buat offer
    Future.delayed(const Duration(milliseconds: 1000), () {
      _createOffer();
    });
  }

  void _handleRemoteOffer(dynamic data) async {
    debugPrint('📨 HANDLING REMOTE OFFER from: ${data['from']}');

    try {
      if (_peerConnection == null) {
        debugPrint('❌ Peer connection not initialized yet');
        return;
      }

      final offer = data['offer'];
      debugPrint('📝 REMOTE SDP: ${offer['sdp']?.toString().substring(0, 100)}...');

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );
      debugPrint('✅ REMOTE DESCRIPTION SET');

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });

      debugPrint('✅ ANSWER CREATED: ${answer.type}');

      await _peerConnection!.setLocalDescription(answer);
      debugPrint('✅ LOCAL DESCRIPTION SET FOR ANSWER');

      // Kirim answer kembali
      debugPrint('📤 SENDING ANSWER to: ${data['from']}');
      socket.emit('answer', {
        'to': data['from'],
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type,
        }
      });

      debugPrint('✅ Answer sent successfully');
    } catch (e) {
      debugPrint('❌ Error handling remote offer: $e');
      _safeCallback(() => onError?.call('Failed to handle call: $e'));
    }
  }

  // Tambahkan remote stream ke UI
  void _addRemoteStream(MediaStream stream) {
    if (_isDisposed) return;

    final renderer = RTCVideoRenderer();

    renderer.initialize().then((_) {
      if (_isDisposed) {
        renderer.dispose();
        return;
      }

      renderer.srcObject = stream;
      final peerId = stream.id;

      _remoteRenderers[peerId] = renderer;
      _remoteStreams.add(renderer);

      // Panggil callback untuk update UI
      _safeCallback(() => onRemoteStream?.call(peerId, stream));
    });
  }

  // Safe callback method
  void _safeCallback(Function() callback) {
    if (!_isDisposed) {
      callback();
    }
  }

  // Public methods untuk UI control
  Future<void> toggleMute() async {
    if (_localStream == null || _isProcessing || _isDisposed) return;

    _isProcessing = true;
    try {
      final audioTracks = _localStream!.getAudioTracks();
      final tracks = List<MediaStreamTrack>.from(audioTracks);

      if (tracks.isNotEmpty) {
        _isMuted = !_isMuted;

        for (final track in tracks) {
          track.enabled = !_isMuted;
        }

        debugPrint('Audio ${_isMuted ? 'muted' : 'unmuted'}');
      }
    } catch (e) {
      debugPrint('Error toggling mute: $e');
      _isMuted = !_isMuted;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> toggleCamera() async {
    if (_localStream == null || _isProcessing || _isDisposed) return;

    _isProcessing = true;
    try {
      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      if (tracks.isNotEmpty) {
        _isCameraOn = !_isCameraOn;

        if (_isCameraOn) {
          await _enableCamera();
        } else {
          await _disableCamera(tracks);
        }

        debugPrint('Camera ${_isCameraOn ? 'enabled' : 'disabled'}');
      }
    } catch (e) {
      debugPrint('Error toggling camera: $e');
      _isCameraOn = !_isCameraOn;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _enableCamera() async {
    try {
      final videoConstraints = {
        'video': {
          'mandatory': {
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '30',
          },
          'facingMode': _currentCamera,
        }
      };

      final newStream = await navigator.mediaDevices.getUserMedia(videoConstraints);
      final newVideoTrack = newStream.getVideoTracks().first;

      // Stop existing video tracks safely
      await _disableCurrentVideoTracks();

      // Add new video track to local stream
      _localStream!.addTrack(newVideoTrack);

      // Replace track in peer connection
      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(newVideoTrack);
          break;
        }
      }

      // Update UI
      _safeCallback(() => onLocalStream?.call(_localStream!));

      // Cleanup temporary stream
      newStream.getTracks().forEach((track) {
        if (track != newVideoTrack) {
          track.stop();
        }
      });
    } catch (e) {
      debugPrint('Error enabling camera: $e');
      rethrow;
    }
  }

  Future<void> _disableCamera(List<MediaStreamTrack> tracks) async {
    try {
      for (final track in tracks) {
        _safeStopTrack(track);
      }

      // Update UI
      _safeCallback(() => onLocalStream?.call(_localStream!));
    } catch (e) {
      debugPrint('Error disabling camera: $e');
      rethrow;
    }
  }

  Future<void> _disableCurrentVideoTracks() async {
    try {
      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      for (final track in tracks) {
        _safeStopTrack(track);
      }
    } catch (e) {
      debugPrint('Error disabling current video tracks: $e');
    }
  }

  void _safeStopTrack(MediaStreamTrack track) {
    try {
      track.stop();
    } catch (e) {
      debugPrint('Error stopping track ${track.id}: $e');
    }
  }

  Future<void> switchCamera() async {
    if (_localStream == null || _isProcessing || _isDisposed) return;

    _isProcessing = true;
    try {
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';
      await _enableCamera();
      debugPrint('Switched camera to: $_currentCamera');
    } catch (e) {
      debugPrint('Error switching camera: $e');
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';
    } finally {
      _isProcessing = false;
    }
  }

  // Getters
  MediaStream? get localStream => _localStream;
  Map<String, RTCVideoRenderer> get remoteRenderers => _remoteRenderers;
  bool get isMuted => _isMuted;
  bool get isCameraOn => _isCameraOn;
  String? get currentRoomId => roomId;
  String? get currentUserId => selfId;

  Future<void> createOfferManually() async {
    debugPrint('🎯 MANUAL OFFER CREATION TRIGGERED');
    await _createOffer();
  }

  // Tambahkan method ini di WebRTCManager
  Future<void> reconnect() async {
    if (_isDisposed) return;

    debugPrint('🔄 Attempting to reconnect...');

    try {
      // Close existing connection
      await _peerConnection?.close();
      _peerConnection = null;

      // Re-initialize media dan connection
      await _getUserMedia();
      await _initializePeerConnection();

      // Create new offer setelah delay
      Future.delayed(const Duration(seconds: 2), () {
        _createOffer();
      });

      debugPrint('✅ Reconnection completed');
    } catch (e) {
      debugPrint('❌ Reconnection failed: $e');
    }
  }
/*  Future<void> reconnect() async {
    if (_isDisposed) return;

    debugPrint('🔄 Attempting to reconnect...');

    try {
      // Close existing connection
      await _peerConnection?.close();
      _peerConnection = null;

      // Re-initialize
      await _initializePeerConnection();

      // Create new offer
      await _createOffer();

      debugPrint('✅ Reconnection completed');
    } catch (e) {
      debugPrint('❌ Reconnection failed: $e');
    }
  }*/

  // Method untuk check connection status
  void checkConnectionStatus() {
    debugPrint('🔍 CONNECTION STATUS CHECK:');
    debugPrint('   - Socket connected: ${socket.connected}');
    debugPrint('   - Peer connection: ${_peerConnection != null}');
    debugPrint('   - Local stream: ${_localStream != null}');
    debugPrint('   - Remote renderers: ${_remoteRenderers.length}');

    if (_peerConnection != null) {
      debugPrint('   - Signaling state: ${_peerConnection!.signalingState}');
      debugPrint('   - Ice connection state: ${_peerConnection!.iceConnectionState}');
      debugPrint('   - Connection state: ${_peerConnection!.connectionState}');
    }
  }

  // Cleanup
  Future<void> disconnect() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _isProcessing = true;

    try {
      // Kirim leave event
      if (socket.connected) {
        socket.emit('leave', roomId);
        socket.disconnect();
      }

      // Stop semua local tracks
      if (_localStream != null) {
        final tracks = _localStream!.getTracks();
        final trackList = List<MediaStreamTrack>.from(tracks);
        for (final track in trackList) {
          _safeStopTrack(track);
        }
        _localStream = null;
      }

      // Cleanup remote renderers
      for (final renderer in _remoteRenderers.values) {
        await renderer.dispose();
      }
      _remoteRenderers.clear();

      for (final renderer in _remoteStreams) {
        await renderer.dispose();
      }
      _remoteStreams.clear();

      // Close main peer connection
      await _peerConnection?.close();
      _peerConnection = null;

      debugPrint('Disconnected from WebRTC session');
    } catch (e) {
      debugPrint('Error during disconnect: $e');
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    disconnect();
  }
}

/* No connect, but good UI
class WebRTCManager {
  late IO.Socket socket;
  String? selfId;
  String? roomId;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _remotePeers = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, MediaStream> _remoteStreams = {};

  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _isProcessing = false;
  String _currentCamera = 'user';

  // Callbacks untuk UI
  Function(RTCVideoRenderer)? onLocalRendererReady;
  Function(String peerId, RTCVideoRenderer)? onRemoteRendererReady;
  Function(String peerId)? onPeerDisconnected;
  Function(String)? onError;
  Function()? onConnected;

  // Tambahkan flag untuk menandai apakah manager sudah di-dispose
  bool _isDisposed = false;

  WebRTCManager();

  Future<void> connect(String signalingUrl, String roomId) async {
    this.roomId = roomId;

    try {
      debugPrint('Connecting to room: $roomId');

      // Setup koneksi socket terlebih dahulu
      _setupSocketConnection(signalingUrl, roomId);

    } catch (e) {
      debugPrint('Error connecting: $e');
      onError?.call('Failed to connect: $e');
    }
  }

  void _setupSocketConnection(String signalingUrl, String roomId) {
    debugPrint('Setting up socket connection to: $signalingUrl');

    socket = IO.io(
      signalingUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    // Setup event handlers sebelum connect
    socket.onConnect((_) {
      if (_isDisposed) return;
      selfId = socket.id;
      debugPrint('✅ Connected to signaling server: $selfId');

      _safeCallback(() {
        onConnected?.call();
      });

      _initializeMediaAndPeerConnection();
    });

    socket.onDisconnect((_) {
      debugPrint('❌ Disconnected from signaling server');
    });

    socket.onError((error) {
      debugPrint('❌ Socket error: $error');
      onError?.call('Socket error: $error');
    });

    // WebRTC signaling events
    socket.on('offer', _handleRemoteOffer);
    socket.on('answer', _handleRemoteAnswer);
    socket.on('ice-candidate', _handleRemoteIceCandidate);
    socket.on('user-joined', _handleUserJoined);
    socket.on('user-left', _handleUserLeft);
    socket.on('all-users', _handleAllUsers);

    debugPrint('Attempting to connect socket...');
    socket.connect();
  }

  // Modify semua callback dengan pengecekan
  void _safeCallback(Function() callback) {
    if (!_isDisposed) {
      callback();
    }
  }

  Future<void> _initializeMediaAndPeerConnection() async {
    try {
      debugPrint('🔄 Initializing media and peer connection...');

      // 1. Dapatkan media stream lokal
      await _getUserMedia();

      // 2. Initialize peer connection
      await _initializePeerConnection();

      debugPrint('✅ Media and peer connection initialized successfully');

    } catch (e) {
      debugPrint('❌ Error initializing media and peer connection: $e');
      onError?.call('Failed to initialize media: $e');
    }
  }

  Future<void> _getUserMedia() async {
    try {
      debugPrint('🎥 Getting user media...');

      final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
        },
        'video': {
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 30},
          'facingMode': _currentCamera,
        }
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      debugPrint('✅ Got local media stream with ${_localStream!.getTracks().length} tracks');
      _localStream!.getTracks().forEach((track) {
        debugPrint('   - Track: ${track.kind}, id: ${track.id}, enabled: ${track.enabled}');
      });

      // Create local renderer dan kirim ke UI
      final localRenderer = RTCVideoRenderer();
      await localRenderer.initialize();
      localRenderer.srcObject = _localStream;

      onLocalRendererReady?.call(localRenderer);

    } catch (e) {
      debugPrint('❌ Error getting user media: $e');
      rethrow;
    }
  }

  Future<void> _initializePeerConnection() async {
    try {
      debugPrint('🔗 Initializing peer connection...');

      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      };

      _peerConnection = await createPeerConnection(configuration);

      // Setup event handlers untuk peer connection
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        debugPrint('🧊 Local ICE candidate: ${candidate.candidate}');
        socket.emit('ice-candidate', {
          'to': roomId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }
        });
      };

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        debugPrint('🎬 Remote track received: ${event.track?.kind}');
        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          final peerId = 'remote_${DateTime.now().millisecondsSinceEpoch}'; // Generate unique ID

          debugPrint('📹 Remote stream added with ${stream.getTracks().length} tracks');

          // Create renderer untuk remote stream
          final remoteRenderer = RTCVideoRenderer();
          remoteRenderer.initialize().then((_) {
            remoteRenderer.srcObject = stream;
            _remoteRenderers[peerId] = remoteRenderer;
            _remoteStreams[peerId] = stream;

            onRemoteRendererReady?.call(peerId, remoteRenderer);
          });
        }
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('🔗 Connection state: $state');
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint('🧊 ICE connection state: $state');
      };

      // Add local stream tracks ke peer connection
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });
        debugPrint('✅ Added local tracks to peer connection');
      }

      // Buat offer untuk bergabung dengan room
      _createOffer();

    } catch (e) {
      debugPrint('❌ Error initializing peer connection: $e');
      rethrow;
    }
  }

  // Handler untuk signaling events
  void _handleAllUsers(dynamic data) {
    debugPrint('👥 All users in room: $data');
    // Jika ada users lain di room, buat offer
    _createOffer();
  }

  void _handleUserJoined(dynamic data) {
    final userId = data['userId'];
    debugPrint('🟢 User joined: $userId');
    // Buat offer untuk user yang baru bergabung
    _createOffer();
  }

  void _handleUserLeft(dynamic data) {
    final peerId = data['userId'];
    debugPrint('🔴 User left: $peerId');

    // Cleanup
    _cleanupPeer(peerId);
    onPeerDisconnected?.call(peerId);
  }

  void _cleanupPeer(String peerId) {
    _remotePeers[peerId]?.close();
    _remotePeers.remove(peerId);

    final renderer = _remoteRenderers[peerId];
    if (renderer != null) {
      renderer.dispose();
      _remoteRenderers.remove(peerId);
    }

    _remoteStreams.remove(peerId);
  }

  void _handleRemoteOffer(dynamic data) async {
    debugPrint('📨 Received remote offer from: ${data['from']}');

    try {
      if (_peerConnection == null) {
        debugPrint('❌ Peer connection not initialized yet');
        return;
      }

      final offer = data['offer'];
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Kirim answer kembali
      socket.emit('answer', {
        'to': data['from'],
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type,
        }
      });

      debugPrint('✅ Sent answer to remote offer');
    } catch (e) {
      debugPrint('❌ Error handling remote offer: $e');
      onError?.call('Failed to handle call: $e');
    }
  }

  void _handleRemoteAnswer(dynamic data) async {
    debugPrint('📨 Received remote answer from: ${data['from']}');

    try {
      if (_peerConnection == null) return;

      final answer = data['answer'];
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );

      debugPrint('✅ Remote answer processed');
    } catch (e) {
      debugPrint('❌ Error handling remote answer: $e');
    }
  }

  void _handleRemoteIceCandidate(dynamic data) async {
    debugPrint('🧊 Received remote ICE candidate from: ${data['from']}');

    try {
      if (_peerConnection == null) return;

      final candidateData = data['candidate'];
      await _peerConnection!.addCandidate(RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      ));

      debugPrint('✅ Remote ICE candidate added');
    } catch (e) {
      debugPrint('❌ Error handling remote ICE candidate: $e');
    }
  }

  Future<void> _createOffer() async {
    if (_peerConnection == null) {
      debugPrint('❌ Peer connection not ready for offer');
      return;
    }

    try {
      debugPrint('📤 Creating offer...');

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Kirim offer ke signaling server
      socket.emit('offer', {
        'to': roomId,
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        }
      });

      debugPrint('✅ Offer created and sent to room: $roomId');
    } catch (e) {
      debugPrint('❌ Error creating offer: $e');
      onError?.call('Failed to start call: $e');
    }
  }

  // Public methods untuk UI control
  Future<void> toggleMute() async {
    if (_localStream == null || _isProcessing) return;

    _isProcessing = true;
    try {
      final audioTracks = _localStream!.getAudioTracks();
      final tracks = List<MediaStreamTrack>.from(audioTracks);

      if (tracks.isNotEmpty) {
        _isMuted = !_isMuted;

        for (final track in tracks) {
          track.enabled = !_isMuted;
        }

        debugPrint('🎤 Audio ${_isMuted ? 'muted' : 'unmuted'}');
      }
    } catch (e) {
      debugPrint('❌ Error toggling mute: $e');
      _isMuted = !_isMuted;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> toggleCamera() async {
    if (_localStream == null || _isProcessing) return;

    _isProcessing = true;
    try {
      _isCameraOn = !_isCameraOn;

      if (_isCameraOn) {
        await _enableCamera();
      } else {
        await _disableCamera();
      }

      debugPrint('📷 Camera ${_isCameraOn ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('❌ Error toggling camera: $e');
      _isCameraOn = !_isCameraOn;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _enableCamera() async {
    try {
      final videoConstraints = {
        'video': {
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 30},
          'facingMode': _currentCamera,
        }
      };

      final newStream = await navigator.mediaDevices.getUserMedia(videoConstraints);
      final newVideoTrack = newStream.getVideoTracks().first;

      // Replace track in peer connection
      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(newVideoTrack);
          break;
        }
      }

      // Replace track in local stream
      final oldVideoTracks = _localStream!.getVideoTracks();
      for (final oldTrack in oldVideoTracks) {
        _localStream!.removeTrack(oldTrack);
        oldTrack.stop();
      }
      _localStream!.addTrack(newVideoTrack);

      // Update local renderer
      final localRenderer = RTCVideoRenderer();
      await localRenderer.initialize();
      localRenderer.srcObject = _localStream;
      onLocalRendererReady?.call(localRenderer);

      // Cleanup temporary stream
      newStream.getTracks().forEach((track) {
        if (track != newVideoTrack) {
          track.stop();
        }
      });
    } catch (e) {
      debugPrint('❌ Error enabling camera: $e');
      rethrow;
    }
  }

  Future<void> _disableCamera() async {
    try {
      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      for (final track in tracks) {
        track.stop();
        _localStream!.removeTrack(track);
      }

      // Update local renderer
      final localRenderer = RTCVideoRenderer();
      await localRenderer.initialize();
      localRenderer.srcObject = _localStream;
      onLocalRendererReady?.call(localRenderer);
    } catch (e) {
      debugPrint('❌ Error disabling camera: $e');
      rethrow;
    }
  }

  Future<void> switchCamera() async {
    if (_localStream == null || _isProcessing) return;

    _isProcessing = true;
    try {
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';
      await _enableCamera();
      debugPrint('🔄 Switched camera to: $_currentCamera');
    } catch (e) {
      debugPrint('❌ Error switching camera: $e');
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';
    } finally {
      _isProcessing = false;
    }
  }

  // Getters
  Map<String, RTCVideoRenderer> get remoteRenderers => _remoteRenderers;
  bool get isMuted => _isMuted;
  bool get isCameraOn => _isCameraOn;
  String? get currentRoomId => roomId;
  String? get currentUserId => selfId;

  Future<void> disconnect() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _isProcessing = true;

    try {
      debugPrint('🔌 Disconnecting...');

      // Kirim leave event
      if (socket.connected) {
        socket.emit('leave', roomId);
        socket.disconnect();
      }

      // Stop semua local tracks
      if (_localStream != null) {
        final tracks = _localStream!.getTracks();
        for (final track in tracks) {
          track.stop();
        }
        _localStream = null;
      }

      // Cleanup remote renderers
      for (final renderer in _remoteRenderers.values) {
        await renderer.dispose();
      }
      _remoteRenderers.clear();
      _remoteStreams.clear();

      // Close main peer connection
      await _peerConnection?.close();
      _peerConnection = null;

      debugPrint('✅ Disconnected from WebRTC session');
    } catch (e) {
      debugPrint('❌ Error during disconnect: $e');
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    disconnect();
  }
}*/
