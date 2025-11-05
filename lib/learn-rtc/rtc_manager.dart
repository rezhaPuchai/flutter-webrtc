import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class RtcManager {
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

  // Callbacks untuk UI
  Function()? onConnected;
  Function(MediaStream)? onLocalStream;
  Function(String peerId, MediaStream)? onRemoteStream;
  Function(String peerId)? onPeerDisconnected;
  Function(String)? onError;

  // Getters
  MediaStream? get localStream => _localStream;
  // Map<String, RTCVideoRenderer> get remoteRenderers => _remoteRenderers;
  bool get isMuted => _isMuted;
  bool get isCameraOn => _isCameraOn;
  // String? get currentRoomId => roomId;
  // String? get currentUserId => selfId;
  String get currentCamera => _currentCamera;
  bool get isProcessing => _isProcessing;



  bool _eglErrorOccurred = false;
  int _eglErrorCount = 0;

  static Map<String, dynamic> get androidConfig {
    return {
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
            'stun:stun2.l.google.com:19302',
          ]
        },
      ],
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceCandidatePoolSize': 1, // Reduce untuk performance

      // TAMBAHKAN: Codec preferences untuk avoid hardware issues
      'codecPreferences': {
        'video': [
          'VP8', // Prioritize VP8 over H.264 untuk compatibility
          'H264',
          'VP9'
        ]
      }
    };
  }

  static Map<String, dynamic> get mediaConstraints {
    return {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'googEchoCancellation': true,
        'googAutoGainControl': true,
        'googNoiseSuppression': true,
        'googHighpassFilter': true,
      },
      'video': {
        'width': {'ideal': 640, 'max': 1280},
        'height': {'ideal': 480, 'max': 720},
        'frameRate': {'ideal': 30, 'max': 60}, // Reduce dari 60 ke 30
        'facingMode': 'user',

        // TAMBAHKAN: Advanced constraints untuk stability
        'deviceId': 'default',
        'groupId': 'default',
      }
    };
  }

  static Map<String, dynamic> get softwareFallbackConfig {
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',

      // Force software codecs
      'forceSoftwareCodecs': true,
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    };
  }


  bool _nativeCrashDetected = false;
  int _nativeCrashCount = 0;

  // FORCE SOFTWARE DECODING CONFIG
  static Map<String, dynamic> get forcedSoftwareConfig {
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',

      // CRITICAL: Force software codecs dan disable hardware acceleration
      'forceSoftwareCodecs': true,
      'preferSoftwareCodecs': true,

      // Disable hardware video encoding/decoding
      'disableHardwareAcceleration': true,

      // Video codec preferences - prioritise software-friendly codecs
      'codecPreferences': {
        'video': [
          'VP8', // Paling compatible untuk software decoding
          'VP9',
          'H264' // H264 baseline profile untuk software fallback
        ]
      },

      // Additional constraints untuk stability
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceCandidatePoolSize': 0, // Reduce memory usage
    };
  }

  // Update media constraints untuk reduce load
  static Map<String, dynamic> get lowProfileMediaConstraints {
    return {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'channelCount': 1, // Mono untuk reduce bandwidth
      },
      'video': {
        'width': {'ideal': 480, 'max': 640},  // Turunkan resolusi
        'height': {'ideal': 360, 'max': 480},
        'frameRate': {'ideal': 20, 'max': 30}, // Turunkan frame rate
        'facingMode': 'user',

        // Advanced constraints untuk stability
        'deviceId': 'default',

        // CRITICAL: Reduce bandwidth dan processing
        'bitrate': 300000, // Limit bitrate
      }
    };
  }

  RtcManager();

  Future<void> connect(String signalingUrl, String roomId) async {
    if (_isDisposed) return;

    this.roomId = roomId;

    try {
      debugPrint('🚀 Connecting to room: $roomId');

      // Ambil media stream lokal terlebih dahulu
      await _getUserMedia();

      // Setup koneksi socket dengan protocol yang benar
      _setupSocketConnection(signalingUrl, roomId);

    } catch (e) {
      debugPrint('❌ Error connect: $e');
      _safeCallback(() => onError?.call('Failed to connect: $e'));
    }
  }

  /*Future<void> _getUserMedia() async {
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

      _localStream!.getTracks().forEach((track) {
        debugPrint('🎥 ${track.kind}: ${track.id}');
      });

      _safeCallback(() => onLocalStream?.call(_localStream!));
    } catch (e) {
      debugPrint('❌ Error getting user media: $e');
      _safeCallback(() => onError?.call('Failed to access camera/microphone: $e'));
      rethrow;
    }
  }*/
  Future<void> _getUserMedia() async {
    if (_isDisposed) return;

    // Gunakan low profile constraints,
    // berjalan baik utk android dan ios untuk handle video codec,
    // jangan dihapus
    // final mediaConstraints = _nativeCrashDetected
    //     ? lowProfileMediaConstraints
    //     : mediaConstraints;

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

      // **VALIDATE LOCAL TRACKS**
      _localStream!.getTracks().forEach((track) {
        if (!_isValidMediaTrack(track)) {
          debugPrint('⚠️ Invalid local track detected: ${track.kind} ${track.id}');
          track.stop();
        }
      });

      _safeCallback(() => onLocalStream?.call(_localStream!));
    } catch (e) {
      debugPrint('❌ Error getting user media: $e');

      // Fallback ke audio-only jika video bermasalah
      if (!_nativeCrashDetected) {
        debugPrint('🔄 Trying audio-only fallback...');
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': mediaConstraints['audio'],
            'video': false
          });
          _safeCallback(() => onLocalStream?.call(_localStream!));
        } catch (e2) {
          debugPrint('❌ Audio-only fallback also failed: $e2');
          _safeCallback(() => onError?.call('Failed to access microphone: $e2'));
        }
      } else {
        _safeCallback(() => onError?.call('Failed to access camera/microphone: $e'));
      }
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
      debugPrint('✅ SOCKET CONNECTED: $selfId to room: $roomId ✅');

      // Join room - sesuai server expect
      debugPrint('📤 EMITTING join event: $roomId');
      socket.emit('join', roomId);

      _safeCallback(() => onConnected?.call());
    });

    socket.onDisconnect((_) {
      debugPrint('❌ SOCKET DISCONNECTED');
    });

    socket.onError((error) {
      debugPrint('❌ SOCKET ERROR: $error');
      _safeCallback(() => onError?.call('Socket error: $error'));
    });

    socket.on('peers', (data) {
      debugPrint('👥 PEERS EVENT: $data');
      _handlePeersEvent(data);
    });

    socket.on('signal', (data) {
      _logSignalDetails(data);
      debugPrint('📨 SIGNAL EVENT: $data');
      _handleSignalEvent(data);
    });

    socket.on('connect', (data) {
      debugPrint('# connect: $data');
      // _handleUserJoined(data);
    });

    socket.on('user-joined', (data) {
      debugPrint('🟢 USER JOINED: $data');
      // _handleUserJoined(data);
    });

    socket.on('user-left', (data) {
      debugPrint('🔴 USER LEFT: $data');
      // _handleUserLeft(data);
    });

    socket.on('peer-left', (data) {
      debugPrint('🔴 USER LEFT: $data');
      _handleUserLeft(data);
    });

    socket.onAny((event, data) {
      debugPrint('📡 [ALL EVENTS - onAny] $event: $data');
    });
  }


  void _handlePeersEvent(dynamic peerIds) {
    if (_isDisposed || _localStream == null) return;

    debugPrint('🎯 Handling peers: $peerIds');

    if (peerIds is List) {
      for (final peerId in peerIds) {
        if (peerId is String && peerId != selfId
            && !_peerConnections.containsKey(peerId)) {
          debugPrint('🔗 Creating peer connection to: $peerId');
          _createPeerConnection(peerId);
        }
      }
    }
  }

  Future<void> _createPeerConnection(String peerId) async {
    if (_isDisposed || _localStream == null) return;
    try {
      debugPrint('🔗 Creating peer connection for: $peerId');

      final configuration = _nativeCrashDetected
          ? forcedSoftwareConfig
          : (_eglErrorOccurred ? softwareFallbackConfig : androidConfig);

      final pc = await createPeerConnection(configuration);
      _peerConnections[peerId] = pc;

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

      pc.onRemoveStream = (MediaStream stream) {
        if (_isDisposed) return;
        debugPrint('🎬 Remote stream onRemoveStream from $peerId: ${stream.id}');
        // _addRemoteStream(peerId, stream);
      };

      pc.onTrack = (RTCTrackEvent event) {
        if (_isDisposed) return;
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_isDisposed || !_peerConnections.containsKey(peerId)) return;

          try {
            if (event.streams.isNotEmpty) {
              final stream = event.streams.first;
              debugPrint('🎬 Remote track added: ${event.track.kind} from $peerId');

              // **VALIDATE TRACK SEBELUM DIPROSES**
              if (_isValidMediaTrack(event.track)) {
                _addRemoteStream(peerId, stream);
              } else {
                debugPrint('⚠️ Skipping invalid media track from $peerId');
              }
            }
          } catch (e) {
            debugPrint('❌ Error in onTrack handler: $e');
            _handleNativeError(e.toString(), peerId);
          }
        });
      };

      pc.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('🔗 Connection state with $peerId: $state');
      };

      pc.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint('🧊 ICE connection state with $peerId: $state');
      };

      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });

      debugPrint('✅ Peer connection created for: $peerId');
    } catch (e, stack) {

      debugPrint('❌ Error creating peer connection: $e');
      print('❌ [SIMULATOR] Error creating peer connection: $e');
      print('Stack: $stack');

      // TAMBAHKAN: Try software fallback pada error
      // **DETECT NATIVE CRASH PATTERNS**
      if (_isNativeCrashError(e.toString())) {
        _nativeCrashDetected = true;
        _nativeCrashCount++;

        if (_nativeCrashCount <= 2) {
          debugPrint('🔄 Native crash detected, retrying with software config...');
          await Future.delayed(const Duration(seconds: 1));
          return _createPeerConnection(peerId);
        }
      }

      _peerConnections.remove(peerId);
    }
  }

  void _addRemoteStream(String peerId, MediaStream stream) {
    if (_isDisposed) return;

    debugPrint('📹 Adding remote stream from $peerId with ${stream.getTracks().length} tracks');

    final renderer = RTCVideoRenderer();

    renderer.initialize().then((_) {
      if (_isDisposed) {
        renderer.dispose();
        return;
      }

      renderer.srcObject = stream;
      _remoteRenderers[peerId] = renderer;

      // Panggil callback untuk update UI
      _safeCallback(() => onRemoteStream?.call(peerId, stream));
      debugPrint('✅ Remote renderer created for: $peerId');
    }).catchError((e) {
      debugPrint('❌ Error initializing remote renderer: $e');
    });
  }



  /*void _handleSignalEvent(dynamic data) async {
    if (_isDisposed) return;

    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    debugPrint('🎯 Handling signal from $from - type: $type');

    // Tambahkan delay untuk memastikan processing order
    await Future.delayed(const Duration(milliseconds: 100));

    // Jika belum ada peer connection, buat dulu dengan retry mechanism
    if (!_peerConnections.containsKey(from)) {
      debugPrint('🆕 Creating peer connection for signal from: $from');
      await _createPeerConnectionWithRetry(from);

      // Tunggu lebih lama setelah membuat peer connection
      await Future.delayed(const Duration(milliseconds: 500));
    }

    final pc = _peerConnections[from];
    if (pc == null) {
      debugPrint('❌ Failed to create peer connection for: $from');
      return;
    }

    try {
      switch (type) {
        case 'offer':
          await _handleRemoteOfferWithRetry(pc, from, signalData);
          break;
        case 'answer':
          await _handleRemoteAnswerWithRetry(pc, signalData);
          break;
        case 'candidate':
          await _handleRemoteCandidateWithRetry(pc, signalData);
          break;
        default:
          debugPrint('❌ Unknown signal type: $type');
      }
    } catch (e) {
      debugPrint('❌ Error handling signal: $e');

      // Retry mechanism untuk signal processing
      debugPrint('🔄 Retrying signal handling in 1 second...');
      Future.delayed(const Duration(seconds: 1), () {
        if (!_isDisposed && _peerConnections.containsKey(from)) {
          _handleSignalEvent(data);
        }
      });
    }
  }*/
  void _handleSignalEvent(dynamic data) async {
    if (_isDisposed) return;

    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    debugPrint('🎯 Handling signal from $from - type: $type');

    // **CRITICAL: Skip processing jika native crash terdeteksi dan kita dalam recovery**
    if (_nativeCrashDetected && _nativeCrashCount >= 2) {
      debugPrint('⚠️ Skipping signal processing due to native crash recovery');
      return;
    }

    // Tambahkan delay lebih lama untuk stability
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      if (!_peerConnections.containsKey(from)) {
        debugPrint('🆕 Creating peer connection for signal from: $from');
        await _createPeerConnectionWithRetry(from);
        await Future.delayed(const Duration(milliseconds: 800)); // Delay lebih lama
      }

      final pc = _peerConnections[from];
      if (pc == null) {
        debugPrint('❌ Failed to create peer connection for: $from');
        return;
      }

      switch (type) {
        case 'offer':
          await _handleRemoteOfferWithRetry(pc, from, signalData);
          break;
        case 'answer':
          await _handleRemoteAnswerWithRetry(pc, signalData);
          break;
        case 'candidate':
          await _handleRemoteCandidateWithRetry(pc, signalData);
          break;
        default:
          debugPrint('❌ Unknown signal type: $type');
      }
    } catch (e) {
      debugPrint('❌ Error handling signal: $e');

      // **JANGAN retry jika ini native crash**
      if (!_isNativeCrashError(e.toString())) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isDisposed && _peerConnections.containsKey(from)) {
            _handleSignalEvent(data);
          }
        });
      }
    }
  }

  Future<void> _createPeerConnectionWithRetry(String peerId) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _createPeerConnection(peerId);
        debugPrint('✅ Successfully created peer connection for: $peerId');
        return;
      } catch (e) {
        retryCount++;
        debugPrint('❌ Failed to create peer connection for $peerId (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          debugPrint('⏳ Retrying in ${retryCount * 500}ms...');
          await Future.delayed(Duration(milliseconds: retryCount * 500));
        }
      }
    }

    if (retryCount >= maxRetries) {
      debugPrint('❌ Failed to create peer connection for $peerId after $maxRetries attempts');
    }
  }

  Future<void> _handleRemoteOfferWithRetry(RTCPeerConnection pc, String from, dynamic offerData) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _handleRemoteOffer(pc, from, offerData);
        debugPrint('✅ Successfully handled offer from: $from');
        return;
      } catch (e) {
        retryCount++;
        debugPrint('❌ Failed to handle offer from $from (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          debugPrint('⏳ Retrying offer handling in ${retryCount * 500}ms...');
          await Future.delayed(Duration(milliseconds: retryCount * 500));
        }
      }
    }
  }

  Future<void> _handleRemoteAnswerWithRetry(RTCPeerConnection pc, dynamic answerData) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _handleRemoteAnswer(pc, answerData);
        debugPrint('✅ Successfully handled answer');
        return;
      } catch (e) {
        retryCount++;
        debugPrint('❌ Failed to handle answer (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          debugPrint('⏳ Retrying answer handling in ${retryCount * 500}ms...');
          await Future.delayed(Duration(milliseconds: retryCount * 500));
        }
      }
    }
  }

  Future<void> _handleRemoteCandidateWithRetry(RTCPeerConnection pc, dynamic candidateData) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _handleRemoteCandidate(pc, candidateData);
        debugPrint('✅ Successfully handled ICE candidate');
        return;
      } catch (e) {
        retryCount++;
        debugPrint('❌ Failed to handle ICE candidate (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          debugPrint('⏳ Retrying candidate handling in ${retryCount * 500}ms...');
          await Future.delayed(Duration(milliseconds: retryCount * 500));
        }
      }
    }
  }

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


  void _handleUserLeft(dynamic peerId) {
    if (_isDisposed) return;

    // final peerId = data['userId'];
    debugPrint('🔴 Cleaning up peer: $peerId');

    _cleanupPeer(peerId);
    _safeCallback(() => onPeerDisconnected?.call(peerId));
  }


  bool _isNativeCrashError(String error) {
    return error.contains('SIGABRT') ||
        error.contains('DecodingQueue') ||
        error.contains('stagefright') ||
        error.contains('mediacodec') ||
        error.contains('EGL') ||
        error.contains('OpenGL');
  }

  bool _isValidMediaTrack(MediaStreamTrack track) {
    try {
      // Basic validation - pastikan track memiliki ID dan kind yang valid
      return track.id!.isNotEmpty && (track.kind == 'audio' || track.kind == 'video');
    } catch (e) {
      return false;
    }
  }

  void _handleNativeError(String error, String peerId) {
    debugPrint('🔄 Handling native error for $peerId: $error');

    // Mark native crash detected
    if (!_nativeCrashDetected) {
      _nativeCrashDetected = true;
    }

    // Cleanup problematic peer connection
    _cleanupPeer(peerId);

    // Notify UI tentang error
    _safeCallback(() => onError?.call('Connection issue with participant. Reconnecting...'));

    // Attempt reconnection setelah delay
    if (!_isDisposed && _nativeCrashCount < 3) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isDisposed && !_peerConnections.containsKey(peerId)) {
          debugPrint('🔄 Reconnecting to $peerId after native error...');
          _createPeerConnection(peerId);
        }
      });
    }
  }



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

      debugPrint('📷 Camera ${_isCameraOn ? 'enabling' : 'disabling'}');

      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      if (tracks.isNotEmpty) {
        for (final track in tracks) {
          track.enabled = _isCameraOn;
          debugPrint(' - Video track ${track.id} ${_isCameraOn ? 'enabled' : 'disabled'}');
        }

        // enable/disable di peer connection senders
        for (final pc in _peerConnections.values) {
          final senders = await pc.getSenders();
          for (final sender in senders) {
            if (sender.track?.kind == 'video' && sender.track != null) {
              sender.track!.enabled = _isCameraOn;
            }
          }
        }
        // Update UI
        _safeCallback(() => onLocalStream?.call(_localStream!));
      } else if (_isCameraOn) {
        // Jika tidak ada video tracks tapi mau enable camera, buat baru
        await _enableCamera();
      }

      debugPrint('✅ Camera ${_isCameraOn ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('❌ Error toggling camera: $e');
      _isCameraOn = !_isCameraOn;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _enableCamera() async {
    try {
      debugPrint('🎥 Enabling camera...');

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

      // Stop existing video tracks yang disabled
      await _disableCurrentVideoTracks();

      // Add new video track to local stream
      _localStream!.addTrack(newVideoTrack);

      // Enable dan replace track di peer connections
      for (final pc in _peerConnections.values) {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(newVideoTrack);
            break;
          }
        }
      }
      // Update UI dengan stream yang baru
      _safeCallback(() => onLocalStream?.call(_localStream!));
      // Cleanup temporary stream
      newStream.getTracks().forEach((track) {
        if (track != newVideoTrack) {
          track.stop();
        }
      });
      debugPrint('✅ Camera enabled successfully');
    } catch (e) {
      debugPrint('❌ Error enabling camera: $e');
      rethrow;
    }
  }

  Future<void> _disableCurrentVideoTracks() async {
    try {
      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      debugPrint('🛑 Stopping ${tracks.length} video track(s)');

      for (final track in tracks) {
        debugPrint(' - Stopping video track: ${track.id}');
        track.stop();
        _localStream!.removeTrack(track);
      }
    } catch (e) {
      debugPrint('❌ Error disabling current video tracks: $e');
    }
  }

  Future<void> toggleSwitchCamera() async {
    if (_localStream == null || _isProcessing || _isDisposed) return;
    _isProcessing = true;
    try {
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';
      debugPrint('🔄 Switching camera to: $_currentCamera');

      // BUAR LOCAL STREAM BARU
      await _createNewLocalStream();

      debugPrint('✅ Camera switched successfully to: $_currentCamera');
    } catch (e) {
      debugPrint('❌ Error switching camera: $e');
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _createNewLocalStream() async {
    try {
      debugPrint('🎥 Creating COMPLETELY NEW local stream...');

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

      // final mediaConstraints = {
      //   'audio': {
      //     'echoCancellation': true,
      //     'noiseSuppression': true,
      //   },
      //   'video': {
      //     'width': {'ideal': 640},
      //     'height': {'ideal': 480},
      //     'frameRate': {'ideal': 30},
      //     'facingMode': _currentCamera,
      //   }
      // };
      /**/
      /*final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googAutoGainControl': true,
          'googNoiseSuppression': true,
          'googHighpassFilter': true,
        },
        'video': {
          'width': {'ideal': 640, 'max': 1280},
          'height': {'ideal': 480, 'max': 720},
          'frameRate': {'ideal': 30, 'max': 60}, // Reduce dari 60 ke 30
          'facingMode': 'user',

          // TAMBAHKAN: Advanced constraints untuk stability
          'deviceId': 'default',
          'groupId': 'default',
        }
      };*/

      // BUAT STREAM BARU
      final newLocalStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      // APPLY MUTE STATE KE STREAM BARU
      if (_isMuted) {
        final audioTracks = newLocalStream.getAudioTracks();
        for (final track in audioTracks) {
          track.enabled = false; // Mute audio tracks baru
        }
        debugPrint('🔇 Applied mute state to new stream');
      }

      // STOP DAN REPLACE LOCAL STREAM LAMA
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
      }

      _localStream = newLocalStream;

      // REPLACE TRACKS DI SEMUA PEER CONNECTIONS
      for (final entry in _peerConnections.entries) {
        final peerId = entry.key;
        final pc = entry.value;

        // Dapatkan semua senders
        final senders = await pc.getSenders();

        // Replace audio track
        final audioTrack = _localStream!.getAudioTracks().firstOrNull;
        if (audioTrack != null) {
          for (final sender in senders) {
            if (sender.track?.kind == 'audio') {
              await sender.replaceTrack(audioTrack);
              break;
            }
          }
        }

        // Replace video track
        final videoTrack = _localStream!.getVideoTracks().firstOrNull;
        if (videoTrack != null) {
          for (final sender in senders) {
            if (sender.track?.kind == 'video') {
              await sender.replaceTrack(videoTrack);
              break;
            }
          }
        }
        debugPrint('✅ Replaced tracks for peer: $peerId');
      }

      // NOTIFY UI TENTANG STREAM BARU
      _safeCallback(() => onLocalStream?.call(_localStream!));
      debugPrint('✅ Completely new local stream created and applied (mute: $_isMuted)');
    } catch (e) {
      debugPrint('❌ Error creating new local stream: $e');
      rethrow;
    }
  }

  void _safeCallback(Function() callback) {
    if (!_isDisposed) {
      callback();
    }
  }
  
  Future<void> disconnect() async {
    if (_isDisposed) return;

    _isDisposed = true;

    try {
      debugPrint('🔌 Disconnecting...');

      // Kirim leave event
      if (socket.connected) {
        socket.emit('leave', roomId);
        socket.disconnect();
      }

      // Cleanup semua peer connections
      for (final peerId in _peerConnections.keys.toList()) {
        _cleanupPeer(peerId);
      }
      _peerConnections.clear();

      // Cleanup semua renderers
      for (final renderer in _remoteRenderers.values) {
        await renderer.dispose();
      }
      _remoteRenderers.clear();

      // Stop semua local tracks
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

  void _cleanupPeer(String peerId) {
    final pc = _peerConnections[peerId];
    if (pc != null) {
      pc.close();
      _peerConnections.remove(peerId);
    }

    final renderer = _remoteRenderers[peerId];
    if (renderer != null) {
      renderer.dispose();
      _remoteRenderers.remove(peerId);
    }

    debugPrint('✅ Cleaned up peer: $peerId');
  }

  void _logSignalDetails(dynamic data) {
    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    debugPrint('''
📨 SIGNAL EVENT DETAILS:
   - From: $from
   - Type: $type
   - Room: $roomId
   - Self: $selfId
   - Timestamp: ${DateTime.now().toIso8601String()}
   - Peer Connections: ${_peerConnections.length}
   - Remote Renderers: ${_remoteRenderers.length}
''');

    if (type == 'offer' || type == 'answer') {
      final sdp = signalData['sdp'];
      if (sdp is String) {
        debugPrint('   - SDP Preview: ${sdp.substring(0, 100)}...');
      }
    }
  }

}