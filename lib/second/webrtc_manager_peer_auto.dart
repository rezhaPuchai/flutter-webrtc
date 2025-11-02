import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class WebRTCManagerPeerAuto {
  late io.Socket socket;
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
      debugPrint('🚀 Connecting to room: $roomId');

      // Reset state untuk new connection
      _isFullyInitialized = false;

      // Setup socket connection terlebih dahulu
      _setupSocketConnection(signalingUrl, roomId);

    } catch (e) {
      debugPrint('❌ Error connecting: $e');
      _safeCallback(() => onError?.call('Failed to connect: $e'));
    }
  }

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

    socket.onConnect((_) {
      if (_isDisposed) return;
      selfId = socket.id;
      debugPrint('✅ SOCKET CONNECTED: $selfId to room: $roomId');

      // Join room
      debugPrint('📤 EMITTING join event: $roomId');
      socket.emit('join', roomId);

      _safeCallback(() => onConnected?.call());

      // Initialize media SETELAH socket connected
      _initializeMediaAndPeerConnection();
    });

    socket.onDisconnect((_) {
      debugPrint('❌ SOCKET DISCONNECTED');
      _isFullyInitialized = false;
    });

    socket.onError((error) {
      debugPrint('❌ SOCKET ERROR: $error');
      _safeCallback(() => onError?.call('Socket error: $error'));
    });

    // Event handlers
    socket.on('peers', (data) {
      debugPrint('👥 PEERS EVENT: $data');
      _handlePeersEvent(data);
    });

    socket.on('signal', (data) {
      debugPrint('📨 SIGNAL EVENT: $data');
      _handleSignalEvent(data);
    });

    socket.on('user-joined', (data) {
      debugPrint('🟢 USER JOINED: $data');
      _handleUserJoined(data);
    });

    socket.on('user-left', (data) {
      debugPrint('🔴 USER LEFT: $data');
      _handleUserLeft(data);
    });

    // Debug events
    socket.onAny((event, data) {
      if (event != 'signal') {
        debugPrint('📡 [ALL EVENTS] $event: $data');
      }
    });
  }

  // **TAMBAHKAN: Method yang missing**
  void _handleSignalEvent(dynamic data) async {
    if (_isDisposed) return;

    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    debugPrint('🎯 Handling signal from $from - type: $type');

    // Jika belum ada peer connection, buat dulu
    if (!_peerConnections.containsKey(from)) {
      debugPrint('🆕 Creating peer connection for signal from: $from');
      await _createPeerConnection(from);
    }

    final pc = _peerConnections[from];
    if (pc == null) {
      debugPrint('❌ Failed to create peer connection for: $from');
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
          debugPrint('❌ Unknown signal type: $type');
      }
    } catch (e) {
      debugPrint('❌ Error handling signal: $e');
    }
  }

  // **TAMBAHKAN: Method yang missing**
  void _handleUserLeft(dynamic data) {
    if (_isDisposed) return;

    final peerId = data['userId'];
    debugPrint('🔴 Cleaning up peer: $peerId');

    _cleanupPeer(peerId);
    _safeCallback(() => onPeerDisconnected?.call(peerId));
  }

  // **TAMBAHKAN: Method yang missing**
  Future<void> _handleRemoteOffer(RTCPeerConnection pc, String from, dynamic offerData) async {
    try {
      debugPrint('📨 Handling offer from $from');

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

      debugPrint('✅ Answer sent to $from');
    } catch (e) {
      debugPrint('❌ Error handling remote offer from $from: $e');
    }
  }

  // **TAMBAHKAN: Method yang missing**
  Future<void> _handleRemoteAnswer(RTCPeerConnection pc, dynamic answerData) async {
    try {
      debugPrint('📨 Handling answer from peer');

      await pc.setRemoteDescription(
        RTCSessionDescription(answerData['sdp'], answerData['type']),
      );

      debugPrint('✅ Answer processed');
    } catch (e) {
      debugPrint('❌ Error handling remote answer: $e');
    }
  }

  // **TAMBAHKAN: Method yang missing**
  Future<void> _handleRemoteCandidate(RTCPeerConnection pc, dynamic candidateData) async {
    try {
      debugPrint('🧊 Handling ICE candidate from peer');

      final candidate = candidateData['candidate'];
      await pc.addCandidate(RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      ));

      debugPrint('✅ ICE candidate added');
    } catch (e) {
      debugPrint('❌ Error handling ICE candidate: $e');
    }
  }

  Future<void> _initializeMediaAndPeerConnection() async {
    try {
      debugPrint('🎯 INITIALIZATION SEQUENCE STARTED');

      // Step 1: Get user media
      await _getUserMedia();

      // Step 2: Initialize main peer connection
      await _initializeMainPeerConnection();

      // Step 3: Mark as fully initialized
      _isFullyInitialized = true;
      debugPrint('✅ FULLY INITIALIZED - Ready for WebRTC connections');

      _safeCallback(() => onReadyForOffers?.call());

    } catch (e) {
      debugPrint('❌ Initialization sequence failed: $e');
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
      debugPrint('✅ Got local media stream with ${_localStream!.getTracks().length} tracks');

      _safeCallback(() => onLocalStream?.call(_localStream!));
    } catch (e) {
      debugPrint('❌ Error getting user media: $e');
      rethrow;
    }
  }

  Future<void> _initializeMainPeerConnection() async {
    if (_isDisposed) return;

    try {
      debugPrint('🔗 Initializing main peer connection configuration');

      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ]
      };

      // Test create peer connection untuk memastikan WebRTC ready
      final testPc = await createPeerConnection(configuration);
      await testPc.close();

      debugPrint('✅ WebRTC peer connection test successful');

    } catch (e) {
      debugPrint('❌ Error initializing main peer connection: $e');
      rethrow;
    }
  }

  void _handlePeersEvent(dynamic peerIds) {
    if (_isDisposed || _localStream == null) return;

    debugPrint('🎯 Handling peers: $peerIds');

    if (!_isFullyInitialized) {
      debugPrint('⏳ Not fully initialized yet, delaying peer connection...');
      Future.delayed(const Duration(seconds: 1), () {
        if (!_isDisposed && _isFullyInitialized) {
          _handlePeersEvent(peerIds);
        }
      });
      return;
    }

    if (peerIds is List) {
      for (final peerId in peerIds) {
        if (peerId is String && peerId != selfId && !_peerConnections.containsKey(peerId)) {
          debugPrint('🔗 Creating peer connection to: $peerId');
          _createPeerConnection(peerId);
        }
      }
    }
  }

  void _handleUserJoined(dynamic data) {
    if (_isDisposed || _localStream == null) return;

    final peerId = data['userId'];

    if (!_isFullyInitialized) {
      debugPrint('⏳ Not fully initialized yet, delaying user joined handling...');
      Future.delayed(const Duration(seconds: 1), () {
        if (!_isDisposed && _isFullyInitialized) {
          _handleUserJoined(data);
        }
      });
      return;
    }

    if (peerId != selfId && !_peerConnections.containsKey(peerId)) {
      debugPrint('🔗 User joined, creating peer connection to: $peerId');
      _createPeerConnection(peerId);
    }
  }

  Future<void> _createPeerConnection(String peerId) async {
    if (_isDisposed || _localStream == null) return;

    try {
      debugPrint('🔗 Creating peer connection for: $peerId');

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
        debugPrint('🧊 ICE Candidate to $peerId: ${candidate.candidate}');

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
        debugPrint('🎬 Remote stream added from $peerId: ${stream.id}');
        _addRemoteStream(peerId, stream);
      };

      pc.onTrack = (RTCTrackEvent event) {
        if (_isDisposed) return;
        debugPrint('🎬 Remote track added from $peerId: ${event.track.kind}');
        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          _addRemoteStream(peerId, stream);
        }
      };

      pc.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('🔗 Connection state with $peerId: $state');
      };

      // Add local tracks
      debugPrint('⏳ Adding local tracks to peer connection...');
      await Future.delayed(const Duration(milliseconds: 100));

      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });

      debugPrint('✅ Peer connection created for: $peerId');

      // Tunggu lebih lama sebelum create offer
      debugPrint('⏳ Waiting before creating offer...');
      await Future.delayed(const Duration(milliseconds: 800));

      if (!_isDisposed && _peerConnections.containsKey(peerId)) {
        debugPrint('🚀 Creating offer to: $peerId');
        await _createOfferToPeer(peerId);
      }

    } catch (e) {
      debugPrint('❌ Error creating peer connection: $e');
    }
  }

  Future<void> _createOfferToPeer(String peerId) async {
    final pc = _peerConnections[peerId];
    if (pc == null) {
      debugPrint('❌ No peer connection for: $peerId');
      return;
    }

    // Cek state untuk avoid multiple simultaneous offers
    if (pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      debugPrint('⚠️ Already have local offer for $peerId, skipping');
      return;
    }

    try {
      debugPrint('📤 Creating offer to: $peerId');

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

      debugPrint('✅ Offer sent to: $peerId');

    } catch (e) {
      debugPrint('❌ Error creating offer to $peerId: $e');

      // Retry setelah delay jika gagal
      debugPrint('🔄 Retrying offer creation in 1 second...');
      Future.delayed(const Duration(seconds: 1), () {
        if (!_isDisposed && _peerConnections.containsKey(peerId)) {
          _createOfferToPeer(peerId);
        }
      });
    }
  }

  void _addRemoteStream(String peerId, MediaStream stream) {
    if (_isDisposed) return;

    debugPrint('📹 Adding remote stream from $peerId with ${stream.getTracks().length} tracks');

    if (_remoteRenderers.containsKey(peerId)) {
      final existingRenderer = _remoteRenderers[peerId];
      existingRenderer?.srcObject = stream;
      debugPrint('✅ Updated existing renderer for: $peerId');
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
      debugPrint('✅ New remote renderer created for: $peerId');
    }).catchError((e) {
      debugPrint('❌ Error initializing remote renderer: $e');
    });
  }

  void _cleanupPeer(String peerId) {
    final pc = _peerConnections[peerId];
    if (pc != null) {
      pc.close();
      _peerConnections.remove(peerId);
      debugPrint('✅ Closed peer connection: $peerId');
    }

    final renderer = _remoteRenderers[peerId];
    if (renderer != null) {
      renderer.dispose();
      _remoteRenderers.remove(peerId);
      debugPrint('✅ Disposed renderer: $peerId');
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
    if (_localStream == null || _isProcessing || _isDisposed) return;

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
      debugPrint('❌ Error enabling camera: $e');
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
      debugPrint('❌ Error disabling camera: $e');
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
      debugPrint('❌ Error disabling current video tracks: $e');
    }
  }

  void _safeStopTrack(MediaStreamTrack track) {
    try {
      track.stop();
    } catch (e) {
      debugPrint('❌ Error stopping track ${track.id}: $e');
    }
  }

  Future<void> switchCamera() async {
    if (_localStream == null || _isProcessing || _isDisposed) return;

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

  // Manual control methods
  Future<void> createOfferManually() async {
    debugPrint('🎯 MANUAL OFFER CREATION TRIGGERED');

    for (final peerId in _peerConnections.keys) {
      await _createOfferToPeer(peerId);
    }
  }

  Future<void> reconnect() async {
    if (_isDisposed) return;

    debugPrint('🔄 Attempting to reconnect...');

    try {
      for (final peerId in _peerConnections.keys.toList()) {
        _cleanupPeer(peerId);
      }

      await _getUserMedia();

      debugPrint('✅ Reconnection completed');
    } catch (e) {
      debugPrint('❌ Reconnection failed: $e');
    }
  }

  Future<void> retryConnections() async {
    if (_isDisposed) return;

    debugPrint('🔄 MANUAL RETRY - Recreating all peer connections');

    // Cleanup existing connections
    for (final peerId in _peerConnections.keys.toList()) {
      _cleanupPeer(peerId);
    }

    // Re-create connections setelah delay
    Future.delayed(const Duration(seconds: 1), () {
      if (!_isDisposed && socket.connected) {
        debugPrint('🔄 Requesting peers list from server...');
        socket.emit('session', {
          'roomId': roomId,
          'data': {'type': 'query'},
        });
      }
    });
  }

  void checkConnectionStatus() {
    debugPrint('🔍 CONNECTION STATUS CHECK:');
    debugPrint('   - Socket connected: ${socket.connected}');
    debugPrint('   - Self ID: $selfId');
    debugPrint('   - Room ID: $roomId');
    debugPrint('   - Local stream: ${_localStream != null}');
    debugPrint('   - Fully initialized: $_isFullyInitialized');
    debugPrint('   - Peer connections: ${_peerConnections.length}');
    debugPrint('   - Remote renderers: ${_remoteRenderers.length}');

    for (final entry in _peerConnections.entries) {
      debugPrint('   - Peer ${entry.key}:');
      debugPrint('     - Signaling state: ${entry.value.signalingState}');
      debugPrint('     - ICE connection state: ${entry.value.iceConnectionState}');
      debugPrint('     - Connection state: ${entry.value.connectionState}');
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
      debugPrint('🔌 Disconnecting...');

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

      debugPrint('✅ Disconnected from WebRTC session');
    } catch (e) {
      debugPrint('❌ Error during disconnect: $e');
    }
  }

  @override
  void dispose() {
    disconnect();
  }
}