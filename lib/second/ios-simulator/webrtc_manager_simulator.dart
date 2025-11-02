import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class WebRTCManagerSimulator {
  late io.Socket socket;
  String? selfId;
  String? roomId;

  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, bool> _streamProcessing = {};
  final Map<String, int> _streamRetryCount = {};

  MediaStream? _localStream;
  bool _isMuted = false;
  bool _isCameraOn = false;
  bool _isProcessing = false;
  bool _isDisposed = false;
  final bool _isSimulatorMode = true;
  final String _currentCamera = 'user';

  // Callbacks untuk UI
  Function(MediaStream)? onLocalStream;
  Function(String peerId, MediaStream)? onRemoteStream;
  Function(String peerId)? onPeerDisconnected;
  Function(String)? onError;
  Function()? onConnected;

  // Track active peers dari server
  final Set<String> _activePeersFromServer = {};
  final Map<String, Timer> _cleanupTimers = {};
  Completer<void>? _disconnectCompleter;

  // State tracking dengan null safety
  final Map<String, RTCSignalingState?> _peerSignalingStates = {};
  final Map<String, RTCIceConnectionState?> _peerIceStates = {};
  final Map<String, RTCPeerConnectionState?> _peerConnectionStates = {};
  final Map<String, DateTime> _peerJoinTimestamps = {};
  final Set<String> _pendingCleanup = {};

  // Stream controller untuk real-time updates
  final StreamController<Map<String, dynamic>> _peerUpdateController =
  StreamController<Map<String, dynamic>>.broadcast();

  // **TAMBAHKAN: Track SDP state untuk prevent race conditions**
  final Map<String, bool> _sdpProcessing = {};
  final Map<String, Completer<void>> _sdpSemaphore = {};

  Stream<Map<String, dynamic>> get peerUpdates => _peerUpdateController.stream;

  WebRTCManagerSimulator() {
    debugPrint('🎮 WebRTCManagerSimulator initialized - SIMULATOR MODE');
  }

  // ========== PUBLIC METHODS ==========

  Future<void> connect(String signalingUrl, String roomId) async {
    if (_isDisposed) return;

    this.roomId = roomId;

    try {
      debugPrint('🚀 [SIMULATOR] Connecting to room: $roomId');

      // Di simulator, setup media placeholder
      await _setupSimulatorMedia();

      // Setup socket connection
      _setupSocketConnection(signalingUrl, roomId);

    } catch (e) {
      debugPrint('❌ Error connecting: $e');
      _safeCallback(() => onError?.call('Failed to connect: $e'));
    }
  }

  Future<void> disconnect() async {
    if (_isDisposed) return;

    debugPrint('🔌 [SIMULATOR] Starting disconnect process...');
    _disconnectCompleter = Completer<void>();
    _isDisposed = true;

    try {
      // Cancel semua cleanup timers
      _cleanupTimers.forEach((peerId, timer) {
        timer.cancel();
      });
      _cleanupTimers.clear();

      // Kirim leave event
      if (socket.connected) {
        debugPrint('📤 [SIMULATOR] Sending leave event...');
        socket.emit('leave', roomId);
        await Future.delayed(const Duration(milliseconds: 300));
        socket.disconnect();
        debugPrint('✅ [SIMULATOR] Socket disconnected');
      }

      // Cleanup semua peer connections
      final peerIds = _peerConnections.keys.toList();
      debugPrint('🧹 [SIMULATOR] Cleaning up ${peerIds.length} peer connections...');

      for (final peerId in peerIds) {
        await _performPeerCleanup(peerId);
      }

      // Clear semua collections
      _peerConnections.clear();
      _remoteRenderers.clear();
      _activePeersFromServer.clear();
      _streamProcessing.clear();
      _streamRetryCount.clear();
      _peerSignalingStates.clear();
      _peerIceStates.clear();
      _peerConnectionStates.clear();
      _peerJoinTimestamps.clear();
      _pendingCleanup.clear();

      // Stop local tracks jika ada
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _safeStopTrack(track);
        });
        _localStream = null;
      }

      debugPrint('✅ [SIMULATOR] Disconnect completed successfully');
      _disconnectCompleter?.complete();

    } catch (e) {
      debugPrint('❌ Error during disconnect: $e');
      _disconnectCompleter?.completeError(e);
    } finally {
      _disconnectCompleter = null;
    }
  }

  Future<void> toggleMute() async {
    if (_isProcessing || _isDisposed) return;

    _isProcessing = true;
    try {
      _isMuted = !_isMuted;
      debugPrint('🎤 [SIMULATOR] Audio ${_isMuted ? 'muted' : 'unmuted'} (simulator only)');
    } catch (e) {
      debugPrint('❌ Error toggling mute: $e');
      _isMuted = !_isMuted;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> toggleCamera() async {
    if (_isProcessing || _isDisposed) return;

    _isProcessing = true;
    try {
      _isCameraOn = !_isCameraOn;
      debugPrint('📷 [SIMULATOR] Camera ${_isCameraOn ? 'enabled' : 'disabled'} (simulator only)');
    } catch (e) {
      debugPrint('❌ Error toggling camera: $e');
      _isCameraOn = !_isCameraOn;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> switchCamera() async {
    debugPrint('🔄 [SIMULATOR] Camera switch not available in simulator');
    _safeCallback(() => onError?.call('Camera switching not available in simulator'));
  }

  Future<void> createOfferManually() async {
    debugPrint('🎯 [SIMULATOR] MANUAL OFFER CREATION TRIGGERED');

    for (final peerId in _peerConnections.keys) {
      await _createOfferToPeer(peerId);
    }
  }

  Future<void> reconnect() async {
    if (_isDisposed) return;

    debugPrint('🔄 [SIMULATOR] Attempting to reconnect...');

    try {
      // Cleanup existing connections
      for (final peerId in _peerConnections.keys.toList()) {
        await _performPeerCleanup(peerId);
      }

      // Re-initialize media placeholder
      await _setupSimulatorMedia();

      debugPrint('✅ [SIMULATOR] Reconnection completed');

    } catch (e) {
      debugPrint('❌ [SIMULATOR] Reconnection failed: $e');
    }
  }

  Future<void> retryConnections() async {
    if (_isDisposed) return;

    debugPrint('🔄 [SIMULATOR] MANUAL RETRY - Recreating all peer connections');

    // Cleanup existing connections
    for (final peerId in _peerConnections.keys.toList()) {
      await _performPeerCleanup(peerId);
    }

    // Re-create connections setelah delay
    Future.delayed(const Duration(seconds: 1), () {
      if (!_isDisposed && socket.connected) {
        debugPrint('🔄 [SIMULATOR] Requesting peers list from server...');
        socket.emit('session', {
          'roomId': roomId,
          'data': {'type': 'query'},
        });
      }
    });
  }

  void checkConnectionStatus() {
    debugPrint('🔍 [SIMULATOR] CONNECTION STATUS CHECK:');
    debugPrint('   - Socket connected: ${socket.connected}');
    debugPrint('   - Self ID: $selfId');
    debugPrint('   - Room ID: $roomId');
    debugPrint('   - Local stream: ${_localStream != null}');
    debugPrint('   - Peer connections: ${_peerConnections.length}');
    debugPrint('   - Remote renderers: ${_remoteRenderers.length}');
    debugPrint('   - Simulator mode: $_isSimulatorMode');

    for (final entry in _peerConnections.entries) {
      debugPrint('   - Peer ${entry.key}:');
      debugPrint('     - Signaling state: ${entry.value.signalingState}');
      debugPrint('     - ICE connection state: ${entry.value.iceConnectionState}');
      debugPrint('     - Connection state: ${entry.value.connectionState}');
    }
  }

  // ========== PRIVATE METHODS ==========

  Future<void> _setupSimulatorMedia() async {
    try {
      debugPrint('🎮 [SIMULATOR] Setting up simulator media placeholder');
      _localStream = await _createPlaceholderMediaStream();
      debugPrint('✅ [SIMULATOR] Simulator media placeholder created');
      _safeCallback(() => onLocalStream?.call(_localStream!));
    } catch (e) {
      debugPrint('❌ [SIMULATOR] Error setting up simulator media: $e');
    }
  }

  Future<MediaStream> _createPlaceholderMediaStream() async {
    try {
      debugPrint('🎮 [SIMULATOR] Creating placeholder media stream');
      try {
        final constraints = <String, dynamic>{
          'audio': false,
          'video': false,
        };
        return await navigator.mediaDevices.getUserMedia(constraints);
      } catch (e) {
        debugPrint('⚠️ [SIMULATOR] Cannot create real media stream: $e');
        throw Exception('Simulator cannot access media devices');
      }
    } catch (e) {
      debugPrint('❌ [SIMULATOR] Error creating placeholder stream: $e');
      rethrow;
    }
  }

  void _setupSocketConnection(String signalingUrl, String roomId) {
    if (_isDisposed) return;

    debugPrint('🔄 [SIMULATOR] Setting up socket connection to: $signalingUrl');

    socket = io.io(
      signalingUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setTimeout(5000)
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      if (_isDisposed) return;
      selfId = socket.id;
      debugPrint('✅ [SIMULATOR] SOCKET CONNECTED: $selfId to room: $roomId');
      debugPrint('📤 [SIMULATOR] EMITTING join event: $roomId');
      socket.emit('join', roomId);
      _safeCallback(() => onConnected?.call());
    });

    socket.onDisconnect((_) {
      debugPrint('❌ [SIMULATOR] SOCKET DISCONNECTED');
    });

    socket.onError((error) {
      debugPrint('❌ [SIMULATOR] SOCKET ERROR: $error');
      _safeCallback(() => onError?.call('Socket error: $error'));
    });

    socket.on('peers', (data) {
      debugPrint('👥 [SIMULATOR] PEERS EVENT: $data');
      _handlePeersEvent(data);
    });

    socket.on('signal', (data) {
      _logSignalDetails(data);
      debugPrint('📨 [SIMULATOR] SIGNAL EVENT: $data');
      _handleSignalEvent(data);
    });

    socket.on('user-joined', (data) {
      debugPrint('🟢 [SIMULATOR] USER JOINED: $data');
      _handleUserJoined(data);
    });

    socket.on('user-left', (data) {
      debugPrint('🔴 [SIMULATOR] USER LEFT: $data');
      _handleUserLeft(data);
    });

    socket.on('room-update', (data) {
      debugPrint('🏠 [SIMULATOR] ROOM UPDATE: $data');
    });

    socket.onAny((event, data) {
      if (event != 'signal') {
        debugPrint('📡 [SIMULATOR] [ALL EVENTS] $event: $data');
      }
    });
  }

  void _handlePeersEvent(dynamic peerIds) {
    if (_isDisposed) return;

    debugPrint('👥 [SIMULATOR] PEERS EVENT: $peerIds');

    final newActivePeers = <String>{};
    if (peerIds is List) {
      for (final peerId in peerIds) {
        if (peerId is String && peerId != selfId) {
          newActivePeers.add(peerId);
        }
      }
    }

    debugPrint('📊 [SIMULATOR] New active peers: $newActivePeers');
    debugPrint('📊 [SIMULATOR] Previous active peers: $_activePeersFromServer');

    // Cari peers yang hilang (left)
    final leftPeers = _activePeersFromServer.difference(newActivePeers);
    if (leftPeers.isNotEmpty) {
      debugPrint('🔴 [SIMULATOR] Peers left: $leftPeers');
      for (final peerId in leftPeers) {
        _schedulePeerCleanup(peerId);
      }
    }

    // Cari peers yang baru join
    final joinedPeers = newActivePeers.difference(_activePeersFromServer);
    if (joinedPeers.isNotEmpty) {
      debugPrint('🟢 [SIMULATOR] Peers joined: $joinedPeers');
    }

    // Update active peers
    _activePeersFromServer.clear();
    _activePeersFromServer.addAll(newActivePeers);

    // Create connections untuk peers baru
    for (final peerId in joinedPeers) {
      if (!_peerConnections.containsKey(peerId)) {
        debugPrint('🔗 [SIMULATOR] Creating peer connection to new peer: $peerId');
        _createPeerConnection(peerId);
      }
    }

    debugPrint('📊 [SIMULATOR] Final active peers: $_activePeersFromServer');
    debugPrint('📊 [SIMULATOR] Current connections: ${_peerConnections.keys}');
  }

  void _handleUserJoined(dynamic data) {
    if (_isDisposed) return;

    final peerId = data['userId'];
    debugPrint('🟢 [SIMULATOR] USER JOINED: $peerId');

    _activePeersFromServer.add(peerId);
    _pendingCleanup.remove(peerId);

    if (peerId != selfId && !_peerConnections.containsKey(peerId)) {
      debugPrint('🔗 [SIMULATOR] User joined, creating peer connection to: $peerId');
      _createPeerConnection(peerId);
    }
  }

  void _handleUserLeft(dynamic data) {
    if (_isDisposed) return;

    final peerId = data['userId'];
    debugPrint('🔴 [SIMULATOR] USER LEFT EVENT: $peerId');

    _activePeersFromServer.remove(peerId);
    _schedulePeerCleanup(peerId);
  }

  void _schedulePeerCleanup(String peerId) {
    _cleanupTimers[peerId]?.cancel();

    _cleanupTimers[peerId] = Timer(const Duration(milliseconds: 500), () {
      _cleanupTimers.remove(peerId);
      _performPeerCleanup(peerId);
    });

    debugPrint('⏰ [SIMULATOR] Scheduled cleanup for peer: $peerId in 500ms');
  }

// **FIX: Enhanced signal event handler dengan SDP state management**
  void _handleSignalEvent(dynamic data) async {
    if (_isDisposed) return;

    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    debugPrint('🎯 [SIMULATOR] Handling signal from $from - type: $type');

    // **FIX: Skip jika sedang processing SDP untuk peer ini**
    if (_sdpProcessing[from] == true) {
      debugPrint('⚠️ [SIMULATOR] SDP already processing for $from, skipping...');
      return;
    }

    // **FIX: Acquire SDP semaphore untuk peer ini**
    await _acquireSdpLock(from);

    try {
      // Jika belum ada peer connection, buat dulu
      if (!_peerConnections.containsKey(from)) {
        debugPrint('🆕 [SIMULATOR] Creating peer connection for signal from: $from');
        await _createPeerConnectionWithRetry(from);
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final pc = _peerConnections[from];
      if (pc == null) {
        debugPrint('❌ [SIMULATOR] Failed to create peer connection for: $from');
        return;
      }

      // **FIX: Cek signaling state sebelum process SDP**
      final signalingState = pc.signalingState;
      debugPrint('📶 [SIMULATOR] Current signaling state for $from: $signalingState');

      switch (type) {
        case 'offer':
          await _handleRemoteOfferWithRetry(pc, from, signalData, signalingState);
          break;
        case 'answer':
          await _handleRemoteAnswerWithRetry(pc, signalData, signalingState);
          break;
        case 'candidate':
          await _handleRemoteCandidateWithRetry(pc, signalData);
          break;
        default:
          debugPrint('❌ [SIMULATOR] Unknown signal type: $type');
      }
    } catch (e) {
      debugPrint('❌ [SIMULATOR] Error handling signal from $from: $e');
    } finally {
      // **FIX: Release SDP semaphore**
      _releaseSdpLock(from);
    }
  }

  // **TAMBAHKAN: SDP locking mechanism untuk prevent race conditions**
  Future<void> _acquireSdpLock(String peerId) async {
    _sdpProcessing[peerId] = true;

    // Jika sudah ada completer, tunggu sampai selesai
    if (_sdpSemaphore.containsKey(peerId)) {
      await _sdpSemaphore[peerId]!.future;
    }

    _sdpSemaphore[peerId] = Completer<void>();
  }

  void _releaseSdpLock(String peerId) {
    _sdpProcessing[peerId] = false;
    _sdpSemaphore[peerId]?.complete();
    _sdpSemaphore.remove(peerId);
  }

  // **TAMBAHKAN: Helper method untuk get peer ID dari connection**
  String? _getPeerIdByConnection(RTCPeerConnection pc) {
    for (final entry in _peerConnections.entries) {
      if (entry.value == pc) {
        return entry.key;
      }
    }
    return null;
  }

  //start

// **FIX: Enhanced peer connection creation dengan proper initialization**
  Future<void> _createPeerConnection(String peerId) async {
    if (_isDisposed || _peerConnections.containsKey(peerId)) {
      debugPrint('⚠️ [SIMULATOR] Skipping peer connection creation for $peerId - already exists or disposed');
      return;
    }

    try {
      debugPrint('🔗 [SIMULATOR] Creating peer connection for: $peerId');

      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'iceTransportPolicy': 'all',
      };

      final pc = await createPeerConnection(configuration);

      if (pc == null) {
        debugPrint('❌ [SIMULATOR] Failed to create peer connection - returned null');
        throw Exception('Peer connection creation returned null');
      }

      _peerConnections[peerId] = pc;

      // **FIX: Initialize state tracking dengan delay untuk pastikan PC ready**
      await Future.delayed(const Duration(milliseconds: 100));

      // **FIX: Safe state assignment dengan null checks**
      _peerSignalingStates[peerId] = pc.signalingState;
      _peerIceStates[peerId] = pc.iceConnectionState;
      _peerConnectionStates[peerId] = pc.connectionState;
      _peerJoinTimestamps[peerId] = DateTime.now();

      // **FIX: Enhanced state logging**
      debugPrint('📊 [SIMULATOR] Initial states for $peerId:');
      debugPrint('   - Signaling: ${pc.signalingState}');
      debugPrint('   - ICE: ${pc.iceConnectionState}');
      debugPrint('   - Connection: ${pc.connectionState}');
      debugPrint('   - Gathering: ${pc.iceGatheringState}');

      // Setup event handlers
      _setupPeerConnectionEvents(pc, peerId);

      debugPrint('✅ [SIMULATOR] Peer connection created and initialized for: $peerId');

      // **FIX: Wait untuk pastikan PC fully ready sebelum create offer**
      await Future.delayed(const Duration(milliseconds: 500));

      if (!_isDisposed && _peerConnections.containsKey(peerId)) {
        await _createOfferToPeer(peerId);
      }

    } catch (e, stack) {
      debugPrint('❌ [SIMULATOR] Error creating peer connection: $e');
      debugPrint('Stack: $stack');
      _peerConnections.remove(peerId);
      rethrow;
    }
  }

  // **FIX: Enhanced ICE candidate handling dengan remote description validation**
  Future<void> _handleRemoteCandidate(RTCPeerConnection pc, dynamic candidateData) async {
    try {
      debugPrint('🧊 [SIMULATOR] Handling ICE candidate from peer');

      RTCSessionDescription? remoteDescription = await pc.getRemoteDescription();

      // **FIX: Validasi remote description sebelum add candidate**
      if (remoteDescription == null) {
        debugPrint('⚠️ [SIMULATOR] Remote description is null, storing candidate for later');

        // **FIX: Store candidate untuk di-add nanti ketika remote description tersedia**
        _storePendingCandidate(pc, candidateData);
        return;
      }

      final candidate = candidateData['candidate'];
      final rtcCandidate = RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'] ?? '',
        candidate['sdpMLineIndex'] ?? 0,
      );

      debugPrint('📍 [SIMULATOR] Adding ICE candidate: ${candidate['candidate']}');

      await pc.addCandidate(rtcCandidate);
      debugPrint('✅ [SIMULATOR] ICE candidate added successfully');

    } catch (e, stack) {
      debugPrint('❌ [SIMULATOR] Error handling ICE candidate: $e');
      debugPrint('Stack: $stack');

      // **FIX: Non-critical error untuk ICE candidates, jangan throw**
      debugPrint('⚠️ [SIMULATOR] ICE candidate error is non-critical, continuing...');
    }
  }

  // **TAMBAHKAN: Pending candidates management**
  final Map<RTCPeerConnection, List<dynamic>> _pendingCandidates = {};

  void _storePendingCandidate(RTCPeerConnection pc, dynamic candidateData) {
    if (!_pendingCandidates.containsKey(pc)) {
      _pendingCandidates[pc] = [];
    }
    _pendingCandidates[pc]!.add(candidateData);
    debugPrint('💾 [SIMULATOR] Stored pending candidate, total: ${_pendingCandidates[pc]!.length}');
  }

  Future<void> _processPendingCandidates(RTCPeerConnection pc) async {
    if (!_pendingCandidates.containsKey(pc) || _pendingCandidates[pc]!.isEmpty) {
      return;
    }

    debugPrint('🔄 [SIMULATOR] Processing ${_pendingCandidates[pc]!.length} pending candidates');

    for (final candidateData in _pendingCandidates[pc]!) {
      try {
        final candidate = candidateData['candidate'];
        final rtcCandidate = RTCIceCandidate(
          candidate['candidate'],
          candidate['sdpMid'] ?? '',
          candidate['sdpMLineIndex'] ?? 0,
        );

        await pc.addCandidate(rtcCandidate);
        debugPrint('✅ [SIMULATOR] Added pending ICE candidate');
      } catch (e) {
        debugPrint('⚠️ [SIMULATOR] Error adding pending candidate: $e');
      }
    }

    _pendingCandidates[pc]!.clear();
    debugPrint('✅ [SIMULATOR] All pending candidates processed');
  }

  // **FIX: Enhanced offer creation dengan state validation dan retry mechanism**
  Future<void> _createOfferToPeer(String peerId) async {
    final pc = _peerConnections[peerId];
    if (pc == null) {
      debugPrint('❌ [SIMULATOR] Peer connection not found for: $peerId');
      return;
    }

    // **FIX: Skip jika sedang processing SDP**
    if (_sdpProcessing[peerId] == true) {
      debugPrint('⚠️ [SIMULATOR] SDP processing in progress for $peerId, skipping offer creation');
      return;
    }

    try {
      debugPrint('📤 [SIMULATOR] Creating offer to: $peerId');

      // **FIX: Enhanced state validation dengan retry mechanism**
      int stateCheckRetries = 0;
      const maxStateCheckRetries = 5;

      while (stateCheckRetries < maxStateCheckRetries) {
        final signalingState = pc.signalingState;
        debugPrint('📶 [SIMULATOR] Signaling state check ${stateCheckRetries + 1}/$maxStateCheckRetries: $signalingState');

        if (signalingState == RTCSignalingState.RTCSignalingStateStable) {
          break;
        }

        if (signalingState == null) {
          debugPrint('⚠️ [SIMULATOR] Signaling state is null, waiting for initialization...');
          await Future.delayed(const Duration(milliseconds: 200));
          stateCheckRetries++;
          continue;
        }

        // Jika bukan state yang diharapkan, tunggu sebentar
        debugPrint('⚠️ [SIMULATOR] Unexpected signaling state: $signalingState, waiting...');
        await Future.delayed(const Duration(milliseconds: 300));
        stateCheckRetries++;
      }

      if (stateCheckRetries >= maxStateCheckRetries) {
        debugPrint('❌ [SIMULATOR] Failed to achieve stable state after $maxStateCheckRetries attempts');

        // **FIX: Force recreate peer connection jika state stuck**
        debugPrint('🔄 [SIMULATOR] Recreating peer connection for $peerId due to state issues');
        await _performPeerCleanup(peerId);
        await Future.delayed(const Duration(seconds: 1));

        if (!_isDisposed && _activePeersFromServer.contains(peerId)) {
          await _createPeerConnection(peerId);
        }
        return;
      }

      debugPrint('✅ [SIMULATOR] Ready to create offer, signaling state: ${pc.signalingState}');

      // **FIX: Create offer dengan error handling**
      final offer = await pc.createOffer();
      debugPrint('📄 [SIMULATOR] Offer created for $peerId');

      await pc.setLocalDescription(offer);
      debugPrint('✅ [SIMULATOR] Local offer set for $peerId');

      // **FIX: Process any pending candidates setelah set local description**
      await _processPendingCandidates(pc);

      // Kirim offer via signal event
      socket.emit('signal', {
        'roomId': roomId,
        'to': peerId,
        'data': {
          'type': 'offer',
          'sdp': offer.sdp,
          // 'type': offer.type,
        }
      });

      debugPrint('✅ [SIMULATOR] Offer sent to: $peerId');

    } catch (e, stack) {
      debugPrint('❌ [SIMULATOR] Error creating offer to $peerId: $e');
      debugPrint('Stack: $stack');

      // **FIX: Enhanced error recovery**
      if (e.toString().contains('state') || e.toString().contains('null') || e.toString().contains('SDP')) {
        debugPrint('🔄 [SIMULATOR] SDP/state error detected, will reset connection for $peerId');
        await _performPeerCleanup(peerId);

        Future.delayed(const Duration(seconds: 2), () {
          if (!_isDisposed && _activePeersFromServer.contains(peerId)) {
            debugPrint('🔄 [SIMULATOR] Recreating connection for $peerId after error');
            _createPeerConnection(peerId);
          }
        });
      }
    }
  }

  // **FIX: Enhanced remote offer handling dengan pending candidates processing**
  Future<void> _handleRemoteOffer(RTCPeerConnection pc, String from, dynamic offerData, RTCSignalingState? currentState) async {
    try {
      debugPrint('📨 [SIMULATOR] Handling offer from $from - current state: $currentState');

      // **FIX: Handle null state**
      if (currentState == null) {
        debugPrint('⚠️ [SIMULATOR] Signaling state is null, waiting for initialization...');
        await Future.delayed(const Duration(milliseconds: 200));
        // Check state again after delay
        currentState = pc.signalingState;
        debugPrint('📶 [SIMULATOR] Signaling state after wait: $currentState');
      }

      // **FIX: Relaxed state validation untuk handle various scenarios**
      if (currentState != RTCSignalingState.RTCSignalingStateStable &&
          currentState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        debugPrint('⚠️ [SIMULATOR] Unexpected state for offer: $currentState, but will attempt to proceed');
      }

      final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
      debugPrint('📄 [SIMULATOR] Setting remote offer for $from');

      await pc.setRemoteDescription(offer);
      debugPrint('✅ [SIMULATOR] Remote offer set for $from');

      // **FIX: Process pending candidates setelah set remote description**
      await _processPendingCandidates(pc);

      final answer = await pc.createAnswer();
      debugPrint('📄 [SIMULATOR] Created answer for $from');

      await pc.setLocalDescription(answer);
      debugPrint('✅ [SIMULATOR] Local answer set for $from');

      // Kirim answer back
      socket.emit('signal', {
        'roomId': roomId,
        'to': from,
        'data': {
          'type': 'answer',
          'sdp': answer.sdp,
          // 'type': answer.type,
        }
      });

      debugPrint('✅ [SIMULATOR] Answer sent to $from');

    } catch (e, stack) {
      debugPrint('❌ [SIMULATOR] Error handling remote offer from $from: $e');
      debugPrint('Stack: $stack');

      // **FIX: Enhanced error recovery**
      if (e.toString().contains('wrong state') || e.toString().contains('stable') || e.toString().contains('null')) {
        debugPrint('🔄 [SIMULATOR] SDP state error, resetting connection for $from');
        await _performPeerCleanup(from);
        Future.delayed(const Duration(seconds: 1), () {
          if (!_isDisposed && _activePeersFromServer.contains(from)) {
            _createPeerConnection(from);
          }
        });
      }
      rethrow;
    }
  }

  // **FIX: Enhanced remote answer handling dengan better error handling**
  Future<void> _handleRemoteAnswer(RTCPeerConnection pc, dynamic answerData, RTCSignalingState? currentState) async {
    try {
      debugPrint('📨 [SIMULATOR] Handling answer from peer - current state: $currentState');

      // **FIX: Handle null state**
      if (currentState == null) {
        debugPrint('⚠️ [SIMULATOR] Signaling state is null, this might indicate an issue');
        // Continue anyway, as sometimes state might be null temporarily
      }

      final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
      debugPrint('📄 [SIMULATOR] Setting remote answer');

      await pc.setRemoteDescription(answer);
      debugPrint('✅ [SIMULATOR] Remote answer processed');

      // **FIX: Process pending candidates setelah set remote description**
      await _processPendingCandidates(pc);

    } catch (e, stack) {
      debugPrint('❌ [SIMULATOR] Error handling remote answer: $e');
      debugPrint('Stack: $stack');

      // **FIX: Non-critical error handling untuk answers**
      if (e.toString().contains('wrong state') || e.toString().contains('stable')) {
        debugPrint('🔄 [SIMULATOR] SDP state error for answer, will retry with new offer');

        final peerId = _getPeerIdByConnection(pc);
        if (peerId != null) {
          Future.delayed(const Duration(seconds: 2), () {
            if (!_isDisposed && _peerConnections.containsKey(peerId)) {
              _createOfferToPeer(peerId);
            }
          });
        }
      }
      // **FIX: Don't rethrow untuk answer errors - mereka kurang critical**
      debugPrint('⚠️ [SIMULATOR] Answer error is non-critical, continuing...');
    }
  }

  // **FIX: Enhanced peer cleanup dengan pending candidates cleanup**
  Future<void> _performPeerCleanup(String peerId) async {
    if ((_isDisposed && !_peerConnections.containsKey(peerId)) || _pendingCleanup.contains(peerId)) {
      return;
    }

    debugPrint('🧹 [SIMULATOR] PERFORMING COMPREHENSIVE CLEANUP FOR PEER: $peerId');

    try {
      _pendingCleanup.add(peerId);

      // Notify UI first
      debugPrint('📢 [SIMULATOR] Notifying UI about peer disconnect: $peerId');
      _safeCallback(() {
        onPeerDisconnected?.call(peerId);
      });

      await Future.delayed(const Duration(milliseconds: 100));

      // Cleanup peer connection
      final pc = _peerConnections[peerId];
      if (pc != null) {
        debugPrint('🔌 [SIMULATOR] Closing peer connection for: $peerId');

        // **FIX: Cleanup pending candidates**
        _pendingCandidates.remove(pc);

        await pc.close();
        _peerConnections.remove(peerId);
        debugPrint('✅ [SIMULATOR] Peer connection closed: $peerId');
      }

      // Cleanup renderer
      final renderer = _remoteRenderers[peerId];
      if (renderer != null) {
        debugPrint('🎬 [SIMULATOR] Disposing renderer for: $peerId');
        await _safeDisposeRenderer(renderer);
        _remoteRenderers.remove(peerId);
        debugPrint('✅ [SIMULATOR] Renderer disposed: $peerId');
      }

      // Comprehensive state cleaning
      _streamProcessing.remove(peerId);
      _streamRetryCount.remove(peerId);
      _peerSignalingStates.remove(peerId);
      _peerIceStates.remove(peerId);
      _peerConnectionStates.remove(peerId);
      _peerJoinTimestamps.remove(peerId);
      _sdpProcessing.remove(peerId);
      _sdpSemaphore.remove(peerId);
      _pendingCleanup.remove(peerId);

      debugPrint('✅ [SIMULATOR] COMPLETE CLEANUP DONE FOR PEER: $peerId');

    } catch (e) {
      debugPrint('❌ [SIMULATOR] Error during peer cleanup: $e');
      _pendingCleanup.remove(peerId);
    }
  }


  //end

  // **FIX: Enhanced retry methods dengan state parameter**
  Future<void> _handleRemoteOfferWithRetry(RTCPeerConnection pc, String from, dynamic offerData, RTCSignalingState? currentState) async {
    int retryCount = 0;
    const maxRetries = 2; // Kurangi retries untuk SDP operations

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _handleRemoteOffer(pc, from, offerData, currentState);
        debugPrint('✅ [SIMULATOR] Successfully handled offer from: $from');
        return;
      } catch (e) {
        retryCount++;
        debugPrint('❌ [SIMULATOR] Failed to handle offer from $from (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          final delay = Duration(milliseconds: retryCount * 1000);
          debugPrint('⏳ [SIMULATOR] Retrying offer handling in ${delay.inMilliseconds}ms...');
          await Future.delayed(delay);
        } else {
          debugPrint('❌ [SIMULATOR] Failed to handle offer from $from after $maxRetries attempts');
        }
      }
    }
  }

  Future<void> _handleRemoteAnswerWithRetry(RTCPeerConnection pc, dynamic answerData, RTCSignalingState? currentState) async {
    int retryCount = 0;
    const maxRetries = 2;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _handleRemoteAnswer(pc, answerData, currentState);
        debugPrint('✅ [SIMULATOR] Successfully handled answer');
        return;
      } catch (e) {
        retryCount++;
        debugPrint('❌ [SIMULATOR] Failed to handle answer (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          final delay = Duration(milliseconds: retryCount * 1000);
          debugPrint('⏳ [SIMULATOR] Retrying answer handling in ${delay.inMilliseconds}ms...');
          await Future.delayed(delay);
        } else {
          debugPrint('❌ [SIMULATOR] Failed to handle answer after $maxRetries attempts');

          // **FIX: Create new offer jika answer gagal**
          final peerId = _getPeerIdByConnection(pc);
          if (peerId != null) {
            debugPrint('🔄 [SIMULATOR] Answer failed, creating new offer to $peerId');
            Future.delayed(const Duration(seconds: 1), () {
              if (!_isDisposed && _peerConnections.containsKey(peerId)) {
                _createOfferToPeer(peerId);
              }
            });
          }
        }
      }
    }
  }

  // **TAMBAHKAN: Method untuk debug SDP states**
  void printSdpStates() {
    debugPrint('''
📊 [SIMULATOR] SDP STATES:
${_peerConnections.entries.map((entry) {
      final peerId = entry.key;
      final pc = entry.value;
      return '''
   - Peer $peerId:
     • Signaling: ${pc.signalingState}
     • ICE: ${pc.iceConnectionState}
     • Connection: ${pc.connectionState}
     • SDP Processing: ${_sdpProcessing[peerId] ?? false}
     • Active: ${_activePeersFromServer.contains(peerId)}
''';
    }).join()}
''');
  }


  void _setupPeerConnectionEvents(RTCPeerConnection pc, String peerId) {
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (_isDisposed) return;
      debugPrint('🧊 [SIMULATOR] ICE Candidate to $peerId: ${candidate.candidate}');

      _safeCallback(() {
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
      });
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (_isDisposed) return;
      debugPrint('🎬 [SIMULATOR] Remote track added from $peerId: ${event.track.kind}');

      Future.delayed(const Duration(milliseconds: 100), () {
        if (event.streams.isNotEmpty && !_isDisposed) {
          final stream = event.streams.first;
          debugPrint('📹 [SIMULATOR] Stream ready from $peerId with ${stream.getTracks().length} tracks');
          _addRemoteStream(peerId, stream);
        }
      });
    };

    pc.onConnectionState = (RTCPeerConnectionState? state) {
      debugPrint('🔗 [SIMULATOR] Connection state with $peerId: $state');
      _peerConnectionStates[peerId] = state;

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {

        debugPrint('⚠️ [SIMULATOR] Connection $state with $peerId, scheduling cleanup');
        if (!_activePeersFromServer.contains(peerId)) {
          _schedulePeerCleanup(peerId);
        }
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState? state) {
      debugPrint('🧊 [SIMULATOR] ICE connection state with $peerId: $state');
      _peerIceStates[peerId] = state;

      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {

        debugPrint('⚠️ [SIMULATOR] ICE connection $state with $peerId');
        if (!_activePeersFromServer.contains(peerId)) {
          _schedulePeerCleanup(peerId);
        }
      }
    };
  }

  void _addRemoteStream(String peerId, MediaStream stream) {
    if (_isDisposed) return;

    if (_streamProcessing[peerId] == true) {
      debugPrint('⚠️ [SIMULATOR] Stream for $peerId already being processed');
      return;
    }

    _streamProcessing[peerId] = true;
    _streamRetryCount[peerId] = (_streamRetryCount[peerId] ?? 0) + 1;

    debugPrint('📹 [SIMULATOR] Adding remote stream from $peerId with ${stream.getTracks().length} tracks');

    if (stream.getTracks().isEmpty) {
      debugPrint('⚠️ [SIMULATOR] Empty stream from $peerId, waiting for tracks...');
      _retryStreamProcessing(peerId, stream);
      return;
    }

    _initializeRemoteRenderer(peerId, stream).then((_) {
      _streamProcessing[peerId] = false;
    }).catchError((e) {
      debugPrint('❌ [SIMULATOR] Error in stream processing for $peerId: $e');
      _streamProcessing[peerId] = false;
      _retryStreamProcessing(peerId, stream);
    });
  }

  Future<void> _initializeRemoteRenderer(String peerId, MediaStream stream) async {
    try {
      debugPrint('🎬 [SIMULATOR] Creating renderer for peer: $peerId');

      final renderer = RTCVideoRenderer();
      await _initializeRendererWithTimeout(renderer);

      if (_isDisposed) {
        await renderer.dispose();
        return;
      }

      if (stream.getTracks().isNotEmpty) {
        renderer.srcObject = stream;
        debugPrint('✅ [SIMULATOR] Stream set for renderer: ${stream.id}');
      } else {
        debugPrint('⚠️ [SIMULATOR] No tracks in stream, skipping renderer setup');
        await renderer.dispose();
        return;
      }

      _remoteRenderers[peerId] = renderer;

      _safeCallback(() {
        onRemoteStream?.call(peerId, stream);
      });

      debugPrint('✅ [SIMULATOR] Remote renderer created successfully for: $peerId');

    } catch (e, stack) {
      debugPrint('❌ [SIMULATOR] Error initializing remote renderer for $peerId: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  Future<void> _initializeRendererWithTimeout(RTCVideoRenderer renderer) async {
    try {
      await renderer.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Renderer initialization timeout');
        },
      );
    } catch (e) {
      debugPrint('❌ [SIMULATOR] Renderer initialization failed: $e');
      await renderer.dispose();
      rethrow;
    }
  }

  void _retryStreamProcessing(String peerId, MediaStream stream) {
    final retryCount = _streamRetryCount[peerId] ?? 0;

    if (retryCount >= 3) {
      debugPrint('❌ [SIMULATOR] Max retries reached for peer: $peerId');
      _streamProcessing[peerId] = false;
      return;
    }

    debugPrint('🔄 [SIMULATOR] Retrying stream processing for $peerId in 1 second...');

    Future.delayed(const Duration(seconds: 1), () {
      if (!_isDisposed && _streamProcessing[peerId] != true) {
        _addRemoteStream(peerId, stream);
      }
    });
  }

  // ========== RETRY MECHANISMS ==========

  Future<void> _createPeerConnectionWithRetry(String peerId) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries && !_isDisposed) {
      try {
        await _createPeerConnection(peerId);
        debugPrint('✅ [SIMULATOR] Successfully created peer connection for: $peerId');
        return;
      } catch (e) {
        retryCount++;
        debugPrint('❌ [SIMULATOR] Failed to create peer connection for $peerId (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
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
        debugPrint('✅ [SIMULATOR] Successfully handled ICE candidate');
        return;
      } catch (e) {
        retryCount++;
        debugPrint('❌ [SIMULATOR] Failed to handle ICE candidate (attempt $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: retryCount * 500));
        }
      }
    }
  }

  // ========== UTILITY METHODS ==========

  void _safeCallback(Function() callback) {
    if (!_isDisposed) {
      try {
        callback();
      } catch (e) {
        debugPrint('❌ [SIMULATOR] Error in callback: $e');
      }
    }
  }

  Future<void> _safeDisposeRenderer(RTCVideoRenderer renderer) async {
    try {
      await renderer.dispose();
    } catch (e) {
      debugPrint('⚠️ [SIMULATOR] Error disposing renderer: $e');
    }
  }

  void _safeStopTrack(MediaStreamTrack track) {
    try {
      track.stop();
    } catch (e) {
      debugPrint('❌ [SIMULATOR] Error stopping track ${track.id}: $e');
    }
  }

  void _logSignalDetails(dynamic data) {
    final from = data['from'];
    final signalData = data['data'];
    final type = signalData['type'];

    debugPrint('''
📨 [SIMULATOR] SIGNAL EVENT DETAILS:
   - From: $from
   - Type: $type
   - Room: $roomId
   - Self: $selfId
   - Timestamp: ${DateTime.now().toIso8601String()}
   - Peer Connections: ${_peerConnections.length}
   - Remote Renderers: ${_remoteRenderers.length}
''');
  }

  bool get isFullyDisconnected => _isDisposed && _peerConnections.isEmpty;

  Future<void> waitForDisconnect() async {
    if (_disconnectCompleter != null) {
      await _disconnectCompleter!.future;
    }
  }

  void forceCleanupPeer(String peerId) {
    debugPrint('🛠️ [SIMULATOR] MANUAL FORCE CLEANUP FOR: $peerId');
    _performPeerCleanup(peerId);
  }

  void printDebugInfo() {
    debugPrint('''
🔍 [SIMULATOR] DEBUG INFO:
   - Active Peers (Server): $_activePeersFromServer
   - Peer Connections: ${_peerConnections.keys}
   - Remote Renderers: ${_remoteRenderers.keys}
   - Stream Processing: ${_streamProcessing.keys}
   - Cleanup Timers: ${_cleanupTimers.keys}
''');
  }

  // ========== GETTERS ==========
  MediaStream? get localStream => _localStream;
  Map<String, RTCVideoRenderer> get remoteRenderers => _remoteRenderers;
  bool get isMuted => _isMuted;
  bool get isCameraOn => _isCameraOn;
  bool get isSimulatorMode => _isSimulatorMode;
  String get currentCamera => _currentCamera;
  String? get currentRoomId => roomId;
  String? get currentUserId => selfId;

  @override
  void dispose() {
    disconnect();
  }
}