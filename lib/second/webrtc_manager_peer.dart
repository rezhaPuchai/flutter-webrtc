import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class WebRTCManagerPeer {
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

  // Callbacks untuk UI
  Function(MediaStream)? onLocalStream;
  Function(String peerId, MediaStream)? onRemoteStream;
  Function(String peerId)? onPeerDisconnected;
  Function(String)? onError;
  Function()? onConnected;

  WebRTCManagerPeer();

  Future<void> connect(String signalingUrl, String roomId) async {
    if (_isDisposed) return;

    this.roomId = roomId;

    try {
      print('🚀 Connecting to room: $roomId');

      // Dapatkan media stream lokal terlebih dahulu
      await _getUserMedia();

      // Setup koneksi socket dengan protocol yang benar
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

    // Event handlers sesuai server protocol
    socket.onConnect((_) {
      if (_isDisposed) return;
      selfId = socket.id;
      print('✅ SOCKET CONNECTED: $selfId to room: $roomId');

      // Join room - sesuai server expect
      print('📤 EMITTING join event: $roomId');
      socket.emit('join', roomId);

      _safeCallback(() => onConnected?.call());
    });

    socket.onDisconnect((_) {
      print('❌ SOCKET DISCONNECTED');
    });

    socket.onError((error) {
      print('❌ SOCKET ERROR: $error');
      _safeCallback(() => onError?.call('Socket error: $error'));
    });

    // **EVENT HANDLER YANG SESUAI SERVER PROTOCOL**

    // Event 'peers' - dapatkan daftar peer yang sudah di room
    socket.on('peers', (data) {
      print('👥 PEERS EVENT: $data');
      _handlePeersEvent(data);
    });

    // Event 'signal' - handle semua signaling (offer, answer, candidate)
    socket.on('signal', (data) {
      _logSignalDetails(data); // **TAMBAHKAN: Detailed logging**
      print('📨 SIGNAL EVENT: $data');
      _handleSignalEvent(data);
    });

    // Event untuk user management
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
      print('📡 [ALL EVENTS] $event: $data');
    });
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

      _localStream!.getTracks().forEach((track) {
        print('   - ${track.kind} track: ${track.id}');
      });

      _safeCallback(() => onLocalStream?.call(_localStream!));
    } catch (e) {
      print('❌ Error getting user media: $e');
      _safeCallback(() => onError?.call('Failed to access camera/microphone: $e'));
      rethrow;
    }
  }

  // Handle 'peers' event - buat koneksi ke setiap peer
  void _handlePeersEvent(dynamic peerIds) {
    if (_isDisposed || _localStream == null) return;

    print('🎯 Handling peers: $peerIds');

    if (peerIds is List) {
      for (final peerId in peerIds) {
        if (peerId is String && peerId != selfId && !_peerConnections.containsKey(peerId)) {
          print('🔗 Creating peer connection to: $peerId');
          _createPeerConnection(peerId);
        }
      }
    }
  }

  // Handle user joined event
  void _handleUserJoined(dynamic data) {
    if (_isDisposed || _localStream == null) return;

    final peerId = data['userId'];
    if (peerId != selfId && !_peerConnections.containsKey(peerId)) {
      print('🔗 User joined, creating peer connection to: $peerId');
      _createPeerConnection(peerId);
    }
  }

  // Handle user left event
  void _handleUserLeft(dynamic data) {
    if (_isDisposed) return;

    final peerId = data['userId'];
    print('🔴 Cleaning up peer: $peerId');

    _cleanupPeer(peerId);
    _safeCallback(() => onPeerDisconnected?.call(peerId));
  }

  // Handle 'signal' event - process offer/answer/candidate
  /*FIXED, dont delete this void _handleSignalEvent(dynamic data) async {
    if (_isDisposed) return;

    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    print('🎯 Handling signal from $from - type: $type');

    final pc = _peerConnections[from];
    if (pc == null) {
      print('❌ No peer connection for: $from, creating one...');
      await _createPeerConnection(from);
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
  }*/
  // Di WebRTCManager, perbaiki _handleSignalEvent:

  final Map<String, bool> _signalProcessing = {};
  void _handleSignalEvent(dynamic data) async {
    if (_isDisposed) return;

    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    print('🎯 Handling signal from $from - type: $type');

    // **PERBAIKAN: Tambahkan delay untuk memastikan processing order**
    await Future.delayed(Duration(milliseconds: 100));

    // Jika belum ada peer connection, buat dulu dengan retry mechanism
    if (!_peerConnections.containsKey(from)) {
      print('🆕 Creating peer connection for signal from: $from');
      await _createPeerConnectionWithRetry(from);

      // **PERBAIKAN: Tunggu lebih lama setelah membuat peer connection**
      await Future.delayed(Duration(milliseconds: 500));
    }

    final pc = _peerConnections[from];
    if (pc == null) {
      print('❌ Failed to create peer connection for: $from');
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
          print('❌ Unknown signal type: $type');
      }
    } catch (e) {
      print('❌ Error handling signal: $e');

      // **PERBAIKAN: Retry mechanism untuk signal processing**
      print('🔄 Retrying signal handling in 1 second...');
      Future.delayed(Duration(seconds: 1), () {
        if (!_isDisposed && _peerConnections.containsKey(from)) {
          _handleSignalEvent(data);
        }
      });
    }
  }

// **TAMBAHKAN: Method dengan retry mechanism**
  Future<void> _createPeerConnectionWithRetry(String peerId) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _createPeerConnection(peerId);
        print('✅ Successfully created peer connection for: $peerId');
        return;
      } catch (e) {
        retryCount++;
        print('❌ Failed to create peer connection for $peerId (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          print('⏳ Retrying in ${retryCount * 500}ms...');
          await Future.delayed(Duration(milliseconds: retryCount * 500));
        }
      }
    }

    if (retryCount >= maxRetries) {
      print('❌ Failed to create peer connection for $peerId after $maxRetries attempts');
    }
  }

// **TAMBAHKAN: Method dengan retry untuk offer handling**
  Future<void> _handleRemoteOfferWithRetry(RTCPeerConnection pc, String from, dynamic offerData) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _handleRemoteOffer(pc, from, offerData);
        print('✅ Successfully handled offer from: $from');
        return;
      } catch (e) {
        retryCount++;
        print('❌ Failed to handle offer from $from (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          print('⏳ Retrying offer handling in ${retryCount * 500}ms...');
          await Future.delayed(Duration(milliseconds: retryCount * 500));
        }
      }
    }
  }

// **TAMBAHKAN: Method dengan retry untuk answer handling**
  Future<void> _handleRemoteAnswerWithRetry(RTCPeerConnection pc, dynamic answerData) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _handleRemoteAnswer(pc, answerData);
        print('✅ Successfully handled answer');
        return;
      } catch (e) {
        retryCount++;
        print('❌ Failed to handle answer (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          print('⏳ Retrying answer handling in ${retryCount * 500}ms...');
          await Future.delayed(Duration(milliseconds: retryCount * 500));
        }
      }
    }
  }

// **TAMBAHKAN: Method dengan retry untuk candidate handling**
  Future<void> _handleRemoteCandidateWithRetry(RTCPeerConnection pc, dynamic candidateData) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _handleRemoteCandidate(pc, candidateData);
        print('✅ Successfully handled ICE candidate');
        return;
      } catch (e) {
        retryCount++;
        print('❌ Failed to handle ICE candidate (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          print('⏳ Retrying candidate handling in ${retryCount * 500}ms...');
          await Future.delayed(Duration(milliseconds: retryCount * 500));
        }
      }
    }
  }

  // **TAMBAHKAN: Method untuk detailed logging**
  void _logSignalDetails(dynamic data) {
    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    print('''
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
        print('   - SDP Preview: ${sdp.substring(0, 100)}...');
      }
    }
  }

  // Buat peer connection untuk peer tertentu
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

      pc.onIceConnectionState = (RTCIceConnectionState state) {
        print('🧊 ICE connection state with $peerId: $state');
      };

      // Add local tracks
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });

      print('✅ Peer connection created for: $peerId');

    } catch (e) {
      print('❌ Error creating peer connection: $e');
    }
  }

  // Buat offer ke peer tertentu (dipanggil setelah peer connection dibuat)
  Future<void> _createOfferToPeer(String peerId) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;

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
    }
  }

  // Handle remote offer
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

  // Handle remote answer
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

  // Handle remote ICE candidate
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

  // Tambahkan remote stream ke UI
  void _addRemoteStream(String peerId, MediaStream stream) {
    if (_isDisposed) return;

    print('📹 Adding remote stream from $peerId with ${stream.getTracks().length} tracks');

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
      print('✅ Remote renderer created for: $peerId');
    }).catchError((e) {
      print('❌ Error initializing remote renderer: $e');
    });
  }

  // Cleanup peer connection
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

    print('✅ Cleaned up peer: $peerId');
  }

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

      print('📷 Camera ${_isCameraOn ? 'enabling' : 'disabling'}');

      // **SIMPLE SOLUTION: Enable/disable video tracks tanpa ganti stream**
      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      if (tracks.isNotEmpty) {
        for (final track in tracks) {
          track.enabled = _isCameraOn;
          print('   - Video track ${track.id} ${_isCameraOn ? 'enabled' : 'disabled'}');
        }

        // **PERBAIKAN: Juga enable/disable di peer connection senders**
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

      print('✅ Camera ${_isCameraOn ? 'enabled' : 'disabled'}');
    } catch (e) {
      print('❌ Error toggling camera: $e');
      _isCameraOn = !_isCameraOn;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _disableCamera() async {
    try {
      print('🎥 Disabling camera with black video...');

      // **PERBAIKAN: Gunakan approach yang berbeda - disable tracks tanpa remove**
      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      for (final track in tracks) {
        // **PERBAIKAN: Daripada stop dan remove, cukup disable track**
        track.enabled = false;
        print('   - Disabled video track: ${track.id}');
      }

      // **PERBAIKAN: Untuk peer connections, jangan replace dengan null**
      // Biarkan track tetap ada tapi disabled, sehingga remote tidak stuck
      for (final pc in _peerConnections.values) {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video' && sender.track != null) {
            // **CRITICAL: Enable/disable track instead of replacing dengan null**
            sender.track!.enabled = false;
          }
        }
      }

      // **PERBAIKAN: Update UI untuk menunjukkan camera mati**
      _safeCallback(() => onLocalStream?.call(_localStream!));

      print('✅ Camera disabled - video tracks disabled (not removed)');
    } catch (e) {
      print('❌ Error disabling camera: $e');
      rethrow;
    }
  }

  Future<void> _enableCamera() async {
    try {
      print('🎥 Enabling camera...');

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

      // **PERBAIKAN: Stop existing video tracks yang disabled**
      await _disableCurrentVideoTracks();

      // Add new video track to local stream
      _localStream!.addTrack(newVideoTrack);

      // **PERBAIKAN: Enable dan replace track di peer connections**
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

      print('✅ Camera enabled successfully');
    } catch (e) {
      print('❌ Error enabling camera: $e');
      rethrow;
    }
  }


  Future<MediaStreamTrack?> _createBlackVideoTrack() async {
    try {
      // **PERBAIKAN: Buat canvas untuk generate black video frame**
      // Karena Flutter WebRTC tidak support langsung create black track,
      // kita akan buat temporary video track dan langsung stop, lalu ganti dengan approach lain

      print('🎥 Creating black video placeholder...');

      // Coba buat video track dengan constraints minimal
      final constraints = {
        'video': {
          'width': 1,
          'height': 1,
          'frameRate': 1,
        }
      };

      try {
        final tempStream = await navigator.mediaDevices.getUserMedia(constraints);
        final videoTrack = tempStream.getVideoTracks().first;

        // **CRITICAL: Stop track immediately untuk membuatnya black/blank**
        videoTrack.stop();

        // Cleanup audio tracks dari temp stream
        tempStream.getAudioTracks().forEach((track) => track.stop());

        return videoTrack;
      } catch (e) {
        print('⚠️ Cannot create black video track: $e');
        return null;
      }
    } catch (e) {
      print('❌ Error creating black video track: $e');
      return null;
    }
  }

  Future<void> _replaceWithBlackVideoTrack() async {
    try {
      // Stop existing video tracks
      await _disableCurrentVideoTracks();

      // **PERBAIKAN: Untuk video mati, kita tidak perlu membuat stream baru**
      // Cukup stop tracks dan notify UI bahwa camera mati
      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      for (final track in tracks) {
        track.stop();
        _localStream!.removeTrack(track);
      }

      // **PERBAIKAN: Untuk peer connections, replace video track dengan null**
      for (final pc in _peerConnections.values) {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(null); // Stop sending video
            break;
          }
        }
      }

      // **PERBAIKAN: Update UI untuk menunjukkan camera mati**
      _safeCallback(() => onLocalStream?.call(_localStream!));

    } catch (e) {
      print('❌ Error replacing with black video track: $e');
      rethrow;
    }
  }


  Future<void> _disableCurrentVideoTracks() async {
    try {
      final videoTracks = _localStream!.getVideoTracks();
      final tracks = List<MediaStreamTrack>.from(videoTracks);

      print('🛑 Stopping ${tracks.length} video track(s)');

      for (final track in tracks) {
        print('   - Stopping video track: ${track.id}');
        track.stop();
        _localStream!.removeTrack(track);
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

// Di WebRTCManager, buat method switchCamera yang lebih aggressive:

  Future<void> switchCamera() async {
    if (_localStream == null || _isProcessing || _isDisposed) return;

    _isProcessing = true;
    try {
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';

      print('🔄 Switching camera to: $_currentCamera');

      // **SOLUSI RADICAL: Buat LOCAL STREAM BARU sepenuhnya**
      await _createNewLocalStream();

      print('✅ Camera switched successfully to: $_currentCamera');
    } catch (e) {
      print('❌ Error switching camera: $e');
      _currentCamera = _currentCamera == 'user' ? 'environment' : 'user';
    } finally {
      _isProcessing = false;
    }
  }
  String get currentCamera => _currentCamera;

  Future<void> _createNewLocalStream() async {
    try {
      print('🎥 Creating COMPLETELY NEW local stream...');

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

      // **BUAT STREAM BARU SEPENUHNYA**
      final newLocalStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      // **PERBAIKAN: APPLY MUTE STATE KE STREAM BARU**
      if (_isMuted) {
        final audioTracks = newLocalStream.getAudioTracks();
        for (final track in audioTracks) {
          track.enabled = false; // Mute audio tracks baru
        }
        print('🔇 Applied mute state to new stream');
      }

      // **STOP DAN REPLACE LOCAL STREAM LAMA**
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
      }

      _localStream = newLocalStream;

      // **REPLACE TRACKS DI SEMUA PEER CONNECTIONS**
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

        print('✅ Replaced tracks for peer: $peerId');
      }

      // **NOTIFY UI TENTANG STREAM BARU**
      _safeCallback(() => onLocalStream?.call(_localStream!));

      print('✅ Completely new local stream created and applied (mute: $_isMuted)');

    } catch (e) {
      print('❌ Error creating new local stream: $e');
      rethrow;
    }
  }

  // Manual control methods untuk debugging
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
      // Cleanup existing connections
      for (final peerId in _peerConnections.keys.toList()) {
        _cleanupPeer(peerId);
      }

      // Re-initialize media
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

  // Cleanup
  Future<void> disconnect() async {
    if (_isDisposed) return;

    _isDisposed = true;

    try {
      print('🔌 Disconnecting...');

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