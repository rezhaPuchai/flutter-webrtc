import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:test_web_rtc/second/ios-simulator/webrtc_manager_simulator.dart';

class VideoCallSimulatorIosScreen extends StatefulWidget {
  final String roomId;

  const VideoCallSimulatorIosScreen({super.key, required this.roomId});

  @override
  State<VideoCallSimulatorIosScreen> createState() => _VideoCallSimulatorIosScreenState();
}

class _VideoCallSimulatorIosScreenState extends State<VideoCallSimulatorIosScreen> {
  final WebRTCManagerSimulator _webRTCManager = WebRTCManagerSimulator();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, DateTime> _rendererTimestamps = {};

  bool _isConnected = false;
  bool _isDisposed = false;
  bool _showControls = true;
  bool _isEndingCall = false;
  StreamSubscription? _peerUpdateSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('🎮 Initializing iOS Simulator VideoCallScreen for room: ${widget.roomId}');
    _initializeWebRTC();
  }

  void _initializeWebRTC() {
    debugPrint('🔧 Setting up WebRTC for iOS Simulator');

    _webRTCManager.onConnected = () {
      debugPrint('✅ Connected to room from iOS simulator');
      if (mounted) {
        setState(() {
          _isConnected = true;
        });
      }
    };

    _webRTCManager.onLocalStream = (stream) {
      debugPrint('📹 Local stream received in simulator (placeholder)');
    };

    _webRTCManager.onRemoteStream = (peerId, stream) async {
      debugPrint('📹 Remote stream ready for: $peerId in simulator');
      await _handleRemoteStream(peerId, stream);
    };

    _webRTCManager.onPeerDisconnected = (peerId) {
      debugPrint('🔴 Peer disconnected callback: $peerId');
      _handlePeerDisconnected(peerId);
    };

    _webRTCManager.onError = (error) {
      debugPrint('❌ WebRTC Error in simulator: $error');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    };

    // Real-time peer updates subscription
    _peerUpdateSubscription = _webRTCManager.peerUpdates.listen((update) {
      debugPrint('🔄 [UI] Peer update received: $update');
      _handlePeerUpdate(update);
    });

    // Connect ke room
    debugPrint('🌐 Connecting to signaling server from iOS simulator...');
    _webRTCManager.connect(
      "https://signaling-websocket.payuung.com",
      widget.roomId,
    );
  }

  void _handlePeerUpdate(Map<String, dynamic> update) {
    final type = update['type'];
    final peerId = update['peerId'];
    final state = update['state'] ?? 'unknown';

    debugPrint('📡 [UI] Peer update - Type: $type, Peer: $peerId, State: $state');

    switch (type) {
      case 'connection_state':
        _handleConnectionStateUpdate(peerId, state);
        break;
      case 'ice_state':
        _handleIceStateUpdate(peerId, state);
        break;
    }
  }

  void _handleConnectionStateUpdate(String peerId, String state) {
    debugPrint('🔗 [UI] Peer $peerId connection state: $state');

    if (state.contains('Failed') || state.contains('Closed') || state.contains('Disconnected')) {
      debugPrint('⚠️ [UI] Peer $peerId connection failed: $state');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isDisposed && _remoteRenderers.containsKey(peerId)) {
          _handlePeerDisconnected(peerId);
        }
      });
    }
  }

  void _handleIceStateUpdate(String peerId, String state) {
    debugPrint('🧊 [UI] Peer $peerId ICE state: $state');

    if (state.contains('Failed') || state.contains('Closed')) {
      debugPrint('⚠️ [UI] Peer $peerId ICE failed: $state');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_isDisposed && _remoteRenderers.containsKey(peerId)) {
          _handlePeerDisconnected(peerId);
        }
      });
    }
  }

  // **FIX: Enhanced peer disconnected handler dengan immediate UI update**
  void _handlePeerDisconnected(String peerId) {
    debugPrint('🔴 [UI] Handling peer disconnected: $peerId');

    if (mounted && !_isDisposed) {
      setState(() {
        final renderer = _remoteRenderers[peerId];
        if (renderer != null) {
          // Async dispose renderer
          _safeDisposeRenderer(renderer);
          _remoteRenderers.remove(peerId);
          _rendererTimestamps.remove(peerId);
          debugPrint('✅ [UI] Removed renderer for peer: $peerId');
        }
      });
      debugPrint('📊 [UI] Updated remote renderers: ${_remoteRenderers.keys}');
    }
  }

  // **FIX: Enhanced remote stream handler dengan duplicate prevention**
  Future<void> _handleRemoteStream(String peerId, MediaStream stream) async {
    if (!mounted || _isDisposed) {
      debugPrint('⚠️ Widget disposed, ignoring remote stream');
      return;
    }

    // **FIX: Cek jika renderer sudah ada - replace yang existing**
    if (_remoteRenderers.containsKey(peerId)) {
      debugPrint('🔄 [UI] Replacing existing renderer for: $peerId');
      final existingRenderer = _remoteRenderers[peerId];
      await _safeDisposeRenderer(existingRenderer!);
    }

    try {
      debugPrint('🎬 [UI] Creating new renderer for peer: $peerId');

      final renderer = RTCVideoRenderer();
      await renderer.initialize();

      if (!mounted || _isDisposed) {
        debugPrint('⚠️ Widget disposed during initialization, cleaning up...');
        await renderer.dispose();
        return;
      }

      renderer.srcObject = stream;

      // **FIX: Update UI state dengan timestamp**
      setState(() {
        _remoteRenderers[peerId] = renderer;
        _rendererTimestamps[peerId] = DateTime.now();
      });

      debugPrint('✅ [UI] Remote renderer created successfully for: $peerId');
      debugPrint('📊 [UI] Current remote renderers: ${_remoteRenderers.keys}');

    } catch (e, stack) {
      debugPrint('❌ [UI] Error handling remote stream: $e');
      debugPrint('Stack: $stack');
    }
  }

  // **FIX: Safe renderer disposal**
  Future<void> _safeDisposeRenderer(RTCVideoRenderer renderer) async {
    try {
      await renderer.dispose();
    } catch (e) {
      debugPrint('⚠️ [UI] Error disposing renderer: $e');
    }
  }

  // **FIX: Enhanced end call dengan better cleanup**
  Future<void> _endCall() async {
    if (_isEndingCall || _isDisposed) return;

    _isEndingCall = true;

    debugPrint('📞 Ending call from iOS simulator...');

    try {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }

      // Cancel subscription terlebih dahulu
      await _peerUpdateSubscription?.cancel();

      // **FIX: Clear renderers sebelum disconnect**
      for (final renderer in _remoteRenderers.values) {
        await _safeDisposeRenderer(renderer);
      }

      setState(() {
        _remoteRenderers.clear();
        _rendererTimestamps.clear();
      });

      // Tunggu disconnect selesai
      await _webRTCManager.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('✅ Disconnect completed, navigating back...');

      if (mounted) {
        Navigator.of(context).pop();
      }

    } catch (e) {
      debugPrint('❌ Error during end call: $e');
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      _isEndingCall = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEndingCall) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Ending call...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // **FIX: Remote videos dengan automatic layout updates**
            _buildRemoteVideos(),

            // Simulator info
            _buildSimulatorBanner(),

            // Connection status
            if (!_isConnected)
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.withOpacity(0.8),
                  child: Text(
                    'iOS Simulator - Connecting to room ${widget.roomId}...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

            // Controls
            if (_showControls) _buildControls(),
          ],
        ),
      ),
    );
  }

  // **FIX: Enhanced remote videos builder dengan automatic empty state**
  Widget _buildRemoteVideos() {
    final remoteCount = _remoteRenderers.length;

    // **FIX: Tampilkan waiting screen jika tidak ada remote videos**
    if (remoteCount == 0) {
      return _buildWaitingScreen();
    }

    // **FIX: Gunakan Key untuk force rebuild ketika jumlah renderers berubah**
    return KeyedSubtree(
      key: ValueKey('remoteVideos_${_remoteRenderers.length}_${DateTime.now().millisecondsSinceEpoch}'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return _buildVideoLayout(remoteCount, constraints);
        },
      ),
    );
  }

  Widget _buildVideoLayout(int remoteCount, BoxConstraints constraints) {
    final availableHeight = constraints.maxHeight;
    final availableWidth = constraints.maxWidth;

    switch (remoteCount) {
      case 1:
        return RTCVideoView(
          _remoteRenderers.values.first,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        );
      case 2:
        return Column(
          children: _remoteRenderers.entries.map((entry) {
            return Expanded(
              child: SizedBox(
                width: availableWidth,
                child: RTCVideoView(
                  entry.value,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            );
          }).toList(),
        );
      default:
        final itemHeight = availableHeight / 2.3;
        final itemWidth = availableWidth / 2;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: itemWidth / itemHeight,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: remoteCount,
          itemBuilder: (context, index) {
            final peerId = _remoteRenderers.keys.elementAt(index);
            final renderer = _remoteRenderers[peerId]!;

            return Container(
              margin: const EdgeInsets.all(1),
              child: RTCVideoView(
                renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            );
          },
        );
    }
  }

  Widget _buildWaitingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.smartphone, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          const Text(
            'iOS Simulator Mode',
            style: TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Waiting for remote participants...',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange),
            ),
            child: Column(
              children: [
                const Text(
                  'Simulator Limitations:',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• No camera/microphone\n• Can receive remote streams\n• WebRTC signaling works\n• Perfect for connection testing',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Text(
                  'Share room ID: ${widget.roomId}',
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulatorBanner() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.orange.withOpacity(0.9),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.smartphone, size: 16, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'iOS SIMULATOR MODE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Remote participants: ${_remoteRenderers.length}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Room: ${widget.roomId}',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: Icons.switch_camera,
                      backgroundColor: Colors.grey,
                      iconColor: Colors.white,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Camera not available in simulator')),
                        );
                      },
                      tooltip: 'Camera not available',
                    ),
                    _buildControlButton(
                      icon: Icons.mic_off,
                      backgroundColor: Colors.grey,
                      iconColor: Colors.white,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Microphone not available in simulator')),
                        );
                      },
                      tooltip: 'Mic not available',
                    ),
                    _buildControlButton(
                      icon: Icons.refresh,
                      backgroundColor: Colors.blue,
                      iconColor: Colors.white,
                      onPressed: _webRTCManager.reconnect,
                      tooltip: 'Reconnect signaling',
                    ),
                    _buildControlButton(
                      icon: Icons.call_end,
                      backgroundColor: Colors.red,
                      iconColor: Colors.white,
                      onPressed: _endCall,
                      tooltip: 'End call',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color backgroundColor,
    required Color iconColor,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: CircleAvatar(
        backgroundColor: backgroundColor,
        radius: 24,
        child: IconButton(
          icon: Icon(icon, size: 20),
          onPressed: onPressed,
          color: iconColor,
        ),
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('🧹 Disposing iOS Simulator VideoCallScreen...');
    _isDisposed = true;
    _isEndingCall = true;

    // Enhanced cleanup sequence
    _peerUpdateSubscription?.cancel();

    for (final renderer in _remoteRenderers.values) {
      _safeDisposeRenderer(renderer);
    }
    _remoteRenderers.clear();
    _rendererTimestamps.clear();

    _webRTCManager.disconnect();

    super.dispose();
  }
}