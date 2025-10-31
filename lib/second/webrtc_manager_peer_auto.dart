import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class WebRTCManagerPeerAuto {
  late IO.Socket socket;
  String? selfId;
  String? roomId;

  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  MediaStream? _localStream;

  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _isProcessing = false;
  bool _isDisposed = false;
  String _currentCamera = 'user';
  bool _isFullyInitialized = false;

  // Callbacks untuk UI
  Function(MediaStream)? onLocalStream;
  Function(String peerId, MediaStream)? onRemoteStream;
  Function(String peerId)? onPeerDisconnected;
  Function(String)? onError;
  Function()? onConnected;
  Function()? onReadyForOffers;

  WebRTCManagerPeerAuto();

  Future<void> connect(String signalingUrl, String roomId) async {
    if (_isDisposed) return;

    this.roomId = roomId;

    try {
      print('🚀 Connecting to room: $roomId');

      // Reset state untuk new connection
      _isFullyInitialized = false;

      // Setup socket connection terlebih dahulu
      _setupSocketConnection(signalingUrl, roomId);

    } catch (e) {
      print('❌ Error connecting: $e');
      _safeCallback(() => onError?.call('Failed to connect: $e'));
    }
  }

  void _setupSocketConnection(String signalingUrl, String roomId) {
    if (_isDisposed) return;

    print('🔄 Setting up socket connection to: $signalingUrl');

    socket = IO.io(
      signalingUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      if (_isDisposed) return;
      selfId = socket.id;
      print('✅ SOCKET CONNECTED: $selfId to room: $roomId');

      // Join room
      print('📤 EMITTING join event: $roomId');
      socket.emit('join', roomId);

      _safeCallback(() => onConnected?.call());

      // Initialize media SETELAH socket connected
      _initializeMediaAndPeerConnection();
    });

    socket.onDisconnect((_) {
      print('❌ SOCKET DISCONNECTED');
      _isFullyInitialized = false;
    });

    socket.onError((error) {
      print('❌ SOCKET ERROR: $error');
      _safeCallback(() => onError?.call('Socket error: $error'));
    });

    // Event handlers
    socket.on('peers', (data) {
      print('👥 PEERS EVENT: $data');
      _handlePeersEvent(data);
    });

    socket.on('signal', (data) {
      print('📨 SIGNAL EVENT: $data');
      _handleSignalEvent(data);
    });

    socket.on('user-joined', (data) {
      print('🟢 USER JOINED: $data');
      _handleUserJoined(data);
    });

    socket.on('user-left', (data) {
      print('🔴 USER LEFT: $data');
      _handleUserLeft(data);
    });

    // Debug events
    socket.onAny((event, data) {
      if (event != 'signal') {
        print('📡 [ALL EVENTS] $event: $data');
      }
    });
  }

  // **TAMBAHKAN: Method yang missing**
  void _handleSignalEvent(dynamic data) async {
    if (_isDisposed) return;

    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    print('🎯 Handling signal from $from - type: $type');

    // Jika belum ada peer connection, buat dulu
    if (!_peerConnections.containsKey(from)) {
      print('🆕 Creating peer connection for signal from: $from');
      await _createPeerConnection(from);
    }

    final pc = _peerConnections[from];
    if (pc == null) {
      print('❌ Failed to create peer connection for: $from');
      return;
    }

    try {
      switch (type) {
        case 'offer':
          await _handleRemoteOffer(pc, from, signalData);
          break;
        case 'answer':
          await _handleRemoteAnswer(pc, signalData);
          break;
        case 'candidate':
          await _handleRemoteCandidate(pc, signalData);
          break;
        default:
          print('❌ Unknown signal type: $type');
      }
    } catch (e) {
      print('❌ Error handling signal: $e');
    }
  }

  // **TAMBAHKAN: Method yang missing**
  void _handleUserLeft(dynamic data) {
    if (_isDisposed) return;

    final peerId = data['userId'];
    print('🔴 Cleaning up peer: $peerId');

    _cleanupPeer(peerId);
    _safeCallback(() => onPeerDisconnected?.call(peerId));
  }

  // **TAMBAHKAN: Method yang missing**
  Future<void> _handleRemoteOffer(RTCPeerConnection pc, String from, dynamic offerData) async {
    try {
      print('📨 Handling offer from $from');

      await pc.setRemoteDescription(
        RTCSessionDescription(offerData['sdp'], offerData['type']),
      );

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      // Kirim answer back
      socket.emit('signal', {
        'roomId': roomId,
        'to': from,
        'data': {
          'type': 'answer',
          'sdp': answer.sdp,
          'type': answer.type,
        }
      });

      print('✅ Answer sent to $from');
    } catch (e) {
      print('❌ Error handling remote offer from $from: $e');
    }
  }

  // **TAMBAHKAN: Method yang missing**
  Future<void> _handleRemoteAnswer(RTCPeerConnection pc, dynamic answerData) async {
    try {
      print('📨 Handling answer from peer');

      await pc.setRemoteDescription(
        RTCSessionDescription(answerData['sdp'], answerData['type']),
      );

      print('✅ Answer processed');
    } catch (e) {
      print('❌ Error handling remote answer: $e');
    }
  }

  // **TAMBAHKAN: Method yang missing**
  Future<void> _handleRemoteCandidate(RTCPeerConnection pc, dynamic candidateData) async {
    try {
      print('🧊 Handling ICE candidate from peer');

      final candidate = candidateData['candidate'];
      await pc.addCandidate(RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      ));

      print('✅ ICE candidate added');
    } catch (e) {
      print('❌ Error handling ICE candidate: $e');
    }
  }

  Future<void> _initializeMediaAndPeerConnection() async {
    try {
      print('🎯 INITIALIZATION SEQUENCE STARTED');

      // Step 1: Get user media
      await _getUserMedia();

      // Step 2: Initialize main peer connection
      await _initializeMainPeerConnection();

      // Step 3: Mark as fully initialized
      _isFullyInitialized = true;
      print('✅ FULLY INITIALIZED - Ready for WebRTC connections');

      _safeCallback(() => onReadyForOffers?.call());

    } catch (e) {
      print('❌ Initialization sequence failed: $e');
      _safeCallback(() => onError?.call('Initialization failed: $e'));
    }
  }

  Future<void> _getUserMedia() async {
    if (_isDisposed) return;

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

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      print('✅ Got local media stream with ${_localStream!.getTracks().length} tracks');

      _safeCallback(() => onLocalStream?.call(_localStream!));
    } catch (e) {
      print('❌ Error getting user media: $e');
      rethrow;
    }
  }

  Future<void> _initializeMainPeerConnection() async {
    if (_isDisposed) return;

    try {
      print('🔗 Initializing main peer connection configuration');

      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ]
      };

      // Test create peer connection untuk memastikan WebRTC ready
      final testPc = await createPeerConnection(configuration);
      await testPc.close();

      print('✅ WebRTC peer connection test successful');

    } catch (e) {
      print('❌ Error initializing main peer connection: $e');
      rethrow;
    }
  }

  void _handlePeersEvent(dynamic peerIds) {
    if (_isDisposed || _localStream == null) return;

    print('🎯 Handling peers: $peerIds');

    if (!_isFullyInitialized) {
      print('⏳ Not fully initialized yet, delaying peer connection...');
      Future.delayed(Duration(seconds: 1), () {
        if (!_isDisposed && _isFullyInitialized) {
          _handlePeersEvent(peerIds);
        }
      });
      return;
    }

    if (peerIds is List) {
      for (final peerId in peerIds) {
        if (peerId is String && peerId != selfId && !_peerConnections.containsKey(peerId)) {
          print('🔗 Creating peer connection to: $peerId');
          _createPeerConnection(peerId);
        }
      }
    }
  }

  void _handleUserJoined(dynamic data) {
    if (_isDisposed || _localStream == null) return;

    final peerId = data['userId'];

    if (!_isFullyInitialized) {
      print('⏳ Not fully initialized yet, delaying user joined handling...');
      Future.delayed(Duration(seconds: 1), () {
        if (!_isDisposed && _isFullyInitialized) {
          _handleUserJoined(data);
        }
      });
      return;
    }

    if (peerId != selfId && !_peerConnections.containsKey(peerId)) {
      print('🔗 User joined, creating peer connection to: $peerId');
      _createPeerConnection(peerId);
    }
  }

  Future<void> _createPeerConnection(String peerId) async {
    if (_isDisposed || _localStream == null) return;

    try {
      print('🔗 Creating peer connection for: $peerId');

      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ]
      };

      final pc = await createPeerConnection(configuration);
      _peerConnections[peerId] = pc;

      // Setup event handlers
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (_isDisposed) return;
        print('🧊 ICE Candidate to $peerId: ${candidate.candidate}');

        socket.emit('signal', {
          'roomId': roomId,
          'to': peerId,
          'data': {
            'type': 'candidate',
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            }
          }
        });
      };

      pc.onAddStream = (MediaStream stream) {
        if (_isDisposed) return;
        print('🎬 Remote stream added from $peerId: ${stream.id}');
        _addRemoteStream(peerId, stream);
      };

      pc.onTrack = (RTCTrackEvent event) {
        if (_isDisposed) return;
        print('🎬 Remote track added from $peerId: ${event.track?.kind}');
        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          _addRemoteStream(peerId, stream);
        }
      };

      pc.onConnectionState = (RTCPeerConnectionState state) {
        print('🔗 Connection state with $peerId: $state');
      };

      // Add local tracks
      print('⏳ Adding local tracks to peer connection...');
      await Future.delayed(Duration(milliseconds: 100));

      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });

      print('✅ Peer connection created for: $peerId');

      // Tunggu lebih lama sebelum create offer
      print('⏳ Waiting before creating offer...');
      await Future.delayed(Duration(milliseconds: 800));

      if (!_isDisposed && _peerConnections.containsKey(peerId)) {
        print('🚀 Creating offer to: $peerId');
        await _createOfferToPeer(peerId);
      }

    } catch (e) {
      print('❌ Error creating peer connection: $e');
    }
  }

  Future<void> _createOfferToPeer(String peerId) async {
    final pc = _peerConnections[peerId];
    if (pc == null) {
      print('❌ No peer connection for: $peerId');
      return;
    }

    // Cek state untuk avoid multiple simultaneous offers
    if (pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      print('⚠️ Already have local offer for $peerId, skipping');
      return;
    }

    try {
      print('📤 Creating offer to: $peerId');

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Kirim offer via signal event
      socket.emit('signal', {
        'roomId': roomId,
        'to': peerId,
        'data': {
          'type': 'offer',
          'sdp': offer.sdp,
          'type': offer.type,
        }
      });

      print('✅ Offer sent to: $peerId');

    } catch (e) {
      print('❌ Error creating offer to $peerId: $e');

      // Retry setelah delay jika gagal
      print('🔄 Retrying offer creation in 1 second...');
      Future.delayed(Duration(seconds: 1), () {
        if (!_isDisposed && _peerConnections.containsKey(peerId)) {
          _createOfferToPeer(peerId);
        }
      });
    }
  }

  void _addRemoteStream(String peerId, MediaStream stream) {
    if (_isDisposed) return;

    print('📹 Adding remote stream from $peerId with ${stream.getTracks().length} tracks');

    if (_remoteRenderers.containsKey(peerId)) {
      final existingRenderer = _remoteRenderers[peerId];
      existingRenderer?.srcObject = stream;
      print('✅ Updated existing renderer for: $peerId');
      return;
    }

    final renderer = RTCVideoRenderer();

    renderer.initialize().then((_) {
      if (_isDisposed) {
        renderer.dispose();
        return;
      }

      renderer.srcObject = stream;
      _remoteRenderers[peerId] = renderer;

      _safeCallback(() => onRemoteStream?.call(peerId, stream));
      print('✅ New remote renderer created for: $peerId');
    }).catchError((e) {
      print('❌ Error initializing remote renderer: $e');
    });
  }

  void _cleanupPeer(String peerId) {
    final pc = _peerConnections[peerId];
    if (pc != null) {
      pc.close();
      _peerConnections.remove(peerId);
      print('✅ Closed peer connection: $peerId');
    }

    final renderer = _remoteRenderers[peerId];
    if (renderer != null) {
      renderer.dispose();
      _remoteRenderers.remove(peerId);
      print('✅ Disposed renderer: $peerId');
    }
  }

  void _safeCallback(Function() callback) {
    if (!_isDisposed) {
      callback();
    }
  }

  // Public methods
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

        print('🎤 Audio ${_isMuted ? 'muted' : 'unmuted'}');
      }
    } catch (e) {
      print('❌ Error toggling mute: $e');
      _isMuted = !_isMuted;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> toggleCamera() async {
    if (_localStream == null || _isProcessing || _isDisposed) return;

    _isProcessing = true;
    try {
      _isCameraOn = !_isCameraOn;

      if (_isCameraOn) {
        await _enableCamera();
      } else {
        await _disableCamera();
      }

      print('📷 Camera ${_isCameraOn ? 'enabled' : 'disabled'}');
    } catch (e) {
      print('❌ Error toggling camera: $e');
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

      await _disableCurrentVideoTracks();
      _localStream!.addTrack(newVideoTrack);

      for (final pc in _peerConnections.values) {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(newVideoTrack);
            break;
          }
        }
      }

      _safeCallback(() => onLocalStream?.call(_localStream!));

      newStream.getTracks().forEach((track) {
        if (track != newVideoTrack) {
          track.stop();
        }
      });
    } catch (e) {
      print('❌ Error enabling camera: $e');
      rethrow;
    }
  }

  Future<void> _disableCamera() async {
    try {
      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      for (final track in tracks) {
        _safeStopTrack(track);
        _localStream!.removeTrack(track);
      }

      _safeCallback(() => onLocalStream?.call(_localStream!));
    } catch (e) {
      print('❌ Error disabling camera: $e');
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
      print('❌ Error disabling current video tracks: $e');
    }
  }

  void _safeStopTrack(MediaStreamTrack track) {
    try {
      track.stop();
    } catch (e) {
      print('❌ Error stopping track ${track.id}: $e');
    }
  }

  Future<void> switchCamera() async {
    if (_localStream == null || _isProcessing || _isDisposed) return;

    _isProcessing = true;
    try {
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';
      await _enableCamera();
      print('🔄 Switched camera to: $_currentCamera');
    } catch (e) {
      print('❌ Error switching camera: $e');
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';
    } finally {
      _isProcessing = false;
    }
  }

  // Manual control methods
  Future<void> createOfferManually() async {
    print('🎯 MANUAL OFFER CREATION TRIGGERED');

    for (final peerId in _peerConnections.keys) {
      await _createOfferToPeer(peerId);
    }
  }

  Future<void> reconnect() async {
    if (_isDisposed) return;

    print('🔄 Attempting to reconnect...');

    try {
      for (final peerId in _peerConnections.keys.toList()) {
        _cleanupPeer(peerId);
      }

      await _getUserMedia();

      print('✅ Reconnection completed');
    } catch (e) {
      print('❌ Reconnection failed: $e');
    }
  }

  Future<void> retryConnections() async {
    if (_isDisposed) return;

    print('🔄 MANUAL RETRY - Recreating all peer connections');

    // Cleanup existing connections
    for (final peerId in _peerConnections.keys.toList()) {
      _cleanupPeer(peerId);
    }

    // Re-create connections setelah delay
    Future.delayed(Duration(seconds: 1), () {
      if (!_isDisposed && socket.connected) {
        print('🔄 Requesting peers list from server...');
        socket.emit('session', {
          'roomId': roomId,
          'data': {'type': 'query'},
        });
      }
    });
  }

  void checkConnectionStatus() {
    print('🔍 CONNECTION STATUS CHECK:');
    print('   - Socket connected: ${socket.connected}');
    print('   - Self ID: $selfId');
    print('   - Room ID: $roomId');
    print('   - Local stream: ${_localStream != null}');
    print('   - Fully initialized: $_isFullyInitialized');
    print('   - Peer connections: ${_peerConnections.length}');
    print('   - Remote renderers: ${_remoteRenderers.length}');

    for (final entry in _peerConnections.entries) {
      print('   - Peer ${entry.key}:');
      print('     - Signaling state: ${entry.value.signalingState}');
      print('     - ICE connection state: ${entry.value.iceConnectionState}');
      print('     - Connection state: ${entry.value.connectionState}');
    }
  }

  // Getters
  MediaStream? get localStream => _localStream;
  Map<String, RTCVideoRenderer> get remoteRenderers => _remoteRenderers;
  bool get isMuted => _isMuted;
  bool get isCameraOn => _isCameraOn;
  String? get currentRoomId => roomId;
  String? get currentUserId => selfId;
  bool get isFullyInitialized => _isFullyInitialized;

  Future<void> disconnect() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _isFullyInitialized = false;

    try {
      print('🔌 Disconnecting...');

      if (socket.connected) {
        socket.emit('leave', roomId);
        socket.disconnect();
      }

      for (final peerId in _peerConnections.keys.toList()) {
        _cleanupPeer(peerId);
      }
      _peerConnections.clear();

      for (final renderer in _remoteRenderers.values) {
        await renderer.dispose();
      }
      _remoteRenderers.clear();

      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          track.stop();
        });
        _localStream = null;
      }

      print('✅ Disconnected from WebRTC session');
    } catch (e) {
      print('❌ Error during disconnect: $e');
    }
  }

  @override
  void dispose() {
    disconnect();
  }
}