
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:test_web_rtc/second/webrtc_manager_peer.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;

  const VideoCallScreen({super.key, required this.roomId});

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  // final WebRTCManagerPeerAuto _webRTCManager = WebRTCManagerPeerAuto();
  final WebRTCManagerPeer _webRTCManager = WebRTCManagerPeer();
  MediaStream? _localStream;
  RTCVideoRenderer? _localRenderer;

  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  bool _isConnected = false;
  bool _isDisposed = false;

  // **TAMBAHKAN: Variabel untuk draggable local video**
  Offset _localVideoPosition = const Offset(20, 100);
  bool _isDragging = false;

  // **TAMBAHKAN: State untuk controls visibility**
  bool _showControls = true;

  // **TAMBAHKAN VARIABLE** di _VideoCallScreenState
  RTCVideoRenderer? _localRendererAlt;
  bool _useAltRenderer = false;

  bool _permissionsChecked = false;


  @override
  void initState() {
    super.initState();
    debugPrint('🚀 Initializing VideoCallScreen for room: ${widget.roomId}');
    // _initializeLocalRenderer();
    // _initializeWebRTC();
    _initializeWithPermissions();

  }

  // **TAMBAHKAN: Method untuk toggle controls visibility**
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  Future<void> _initializeWithPermissions() async {
    try {
      // Step 1: Initialize renderers first (aman tanpa permission)
      await _initializeLocalRenderer();
      debugPrint('✅ Local renderer initialized');

      // Step 2: Check and request permissions if needed
      final cameraStatus = await Permission.camera.status;
      final micStatus = await Permission.microphone.status;

      debugPrint('📊 Permission status - Camera: $cameraStatus, Mic: $micStatus');

      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        debugPrint('🔄 Requesting permissions...');
        final statuses = await [Permission.camera, Permission.microphone].request();

        if (statuses[Permission.camera]?.isGranted == true &&
            statuses[Permission.microphone]?.isGranted == true) {
          debugPrint('✅ Permissions granted, initializing WebRTC...');
          // Tunggu sebentar sebelum initialize WebRTC
          await Future.delayed(const Duration(milliseconds: 300));
          _initializeWebRTC();
        } else {
          debugPrint('❌ Permissions denied');
          _showPermissionError();
          return;
        }
      } else {
        // Permissions already granted, langsung initialize WebRTC
        debugPrint('✅ Permissions already granted, initializing WebRTC...');
        _initializeWebRTC();
      }

      setState(() {
        _permissionsChecked = true;
      });

    } catch (e) {
      debugPrint('❌ Initialization error: $e');
      _showError('Initialization failed: $e');
    }
  }

  Future<void> _initializeLocalRenderer() async {
    try {
      _localRenderer = RTCVideoRenderer();
      await _localRenderer!.initialize();

      _localRendererAlt = RTCVideoRenderer();
      await _localRendererAlt!.initialize();

      debugPrint('✅ Local renderer initialized');
    } catch (e) {
      debugPrint('❌ Error initializing local renderer: $e');
    }
  }

  void _initializeWebRTC() {
    debugPrint('🔧 Setting up WebRTC callbacks');

    _webRTCManager.onConnected = () {
      debugPrint('✅ Connected to room');
      setState(() {
        _isConnected = true;
      });
    };

    _webRTCManager.onLocalStream = (stream) {
      debugPrint('📹 LOCAL STREAM UPDATED - Refreshing UI');

      setState(() {
        _localStream = stream;
        if (_localRenderer != null) {
          _localRenderer!.srcObject = stream;
          debugPrint('✅ Local renderer updated with new stream');
        }
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {});
          debugPrint('✅ Extra UI refresh completed');
        }
      });
    };

    _webRTCManager.onRemoteStream = (peerId, stream) async {
      debugPrint('📹 Remote stream ready for: $peerId');

      try {
        final renderer = RTCVideoRenderer();
        await renderer.initialize();

        if (mounted && !_isDisposed) {
          renderer.srcObject = stream;
          setState(() {
            _remoteRenderers[peerId] = renderer;
          });
          debugPrint('✅ Remote renderer created for: $peerId');
        } else {
          renderer.dispose();
        }
      } catch (e) {
        debugPrint('❌ Error creating remote renderer: $e');
      }
    };

    _webRTCManager.onPeerDisconnected = (peerId) {
      debugPrint('🔴 Peer disconnected: $peerId');
      setState(() {
        final renderer = _remoteRenderers[peerId];
        if (renderer != null) {
          renderer.dispose();
          _remoteRenderers.remove(peerId);
        }
      });
    };

    _webRTCManager.onError = (error) {
      debugPrint('❌ WebRTC Error: $error');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    };

    // Connect ke room
    debugPrint('🌐 Connecting to signaling server...');
    _webRTCManager.connect(
      "https://signaling-websocket.payuung.com",
      widget.roomId,
    );
  }

  void _showPermissionError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text('Camera and microphone access is required for video call.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      ).then((_) {
        Navigator.pop(context); // Kembali ke previous screen
      });
    });
  }

  void _showError(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionsChecked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Checking permissions...',
                style: TextStyle(color: Colors.white),
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
          // **TOGGLE CONTROLS VISIBILITY KETIKA TAP DI SEMBARANG TEMPAT**
          _toggleControls(); // atau _toggleControlsWithAutoHide()
        },
        behavior: HitTestBehavior.opaque, // **DETECT TAP DI SEMUA AREA**
        child: Stack(
          children: [
            // Remote videos (full screen background)
            _buildRemoteVideos(),
        
            // **PERBAIKAN: Draggable Local Video**
            if (_localRenderer != null && _localStream != null)
              _buildDraggableLocalVideo(),
        
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
                    'Connecting to room ${widget.roomId}...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
        
            // Room info
            if (_isConnected)
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.video_call, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Room: ${widget.roomId}',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // **PERBAIKAN: Controls dengan conditional visibility**
            if (_showControls) _buildControls(),
          ],
        ),
      ),
    );
  }

/*  Widget _buildRemoteVideos() {
    if (_remoteRenderers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              'Waiting for other participants...',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (_isConnected)
              Text(
                'Share this room ID: ${widget.roomId}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
          ],
        ),
      );
    }

    // Jika hanya 1 remote video, tampilkan full screen
    if (_remoteRenderers.length == 1) {
      final renderer = _remoteRenderers.values.first;
      return RTCVideoView(
        renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    // Jika multiple remote videos, tampilkan dalam grid
    return GridView.count(
      crossAxisCount: 2,
      children: _remoteRenderers.entries.map((entry) {
        return Container(
          margin: const EdgeInsets.all(4),
          child: RTCVideoView(
            entry.value,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        );
      }).toList(),
    );
  }*/
  Widget _buildRemoteVideos() {
    final remoteCount = _remoteRenderers.length;

    if (remoteCount == 0) {
      return _buildWaitingScreen();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final availableWidth = constraints.maxWidth;

        // **CASE 1: Single participant - Fullscreen**
        if (remoteCount == 1) {
          return RTCVideoView(
            _remoteRenderers.values.first,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          );
        }

        // **CASE 2: Two participants - Vertical split**
        if (remoteCount == 2) {
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
        }

        // **CASE 3: Three or more participants - Grid 2 columns**
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
      },
    );
  }

  Widget _buildWaitingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            'Waiting for other participants...',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (_isConnected)
            Text(
              'Share this room ID: ${widget.roomId}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
        ],
      ),
    );
  }

  // **PERBAIKAN: Draggable Local Video Widget**
  Widget _buildDraggableLocalVideo() {
    return Positioned(
      left: _localVideoPosition.dx,
      top: _localVideoPosition.dy,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isDragging = true;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _localVideoPosition += details.delta;

            // Batasi agar tidak keluar dari screen
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;

            _localVideoPosition = Offset(
              _localVideoPosition.dx.clamp(0.0, screenWidth - 120),
              _localVideoPosition.dy.clamp(0.0, screenHeight - 160),
            );
          });
        },
        onPanEnd: (details) {
          setState(() {
            _isDragging = false;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 120,
          height: 160,
          decoration: BoxDecoration(
            border: Border.all(
              color: _isDragging ? Colors.blue : Colors.white,
              width: _isDragging ? 3 : 2,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _buildLocalVideoContent(),
          ),
        ),
      ),
    );
  }

  // fixed, dont delete
  /*Widget _buildLocalVideoContent() {
    // **PERBAIKAN: Cek apakah camera aktif berdasarkan track enabled state**
    bool isCameraActive = false;

    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        // Camera aktif jika ada video track DAN track enabled
        isCameraActive = videoTracks.any((track) => track.enabled);
      }
    }

    if (!isCameraActive) {
      // **TAMPILAN KETIKA CAMERA MATI: Black screen dengan icon**
      return Container(
        color: Colors.black,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off,
              size: 32,
              color: Colors.white54,
            ),
            SizedBox(height: 8),
            Text(
              'Camera Off',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    // **TAMPILAN KETIKA CAMERA AKTIF: Video normal**
    return RTCVideoView(
      _localRenderer!,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      mirror: true,
    );
  }*/
  Widget _buildLocalVideoContent() {
    // **PERBAIKAN: Handle case ketika renderer sedang di-recreate**
    if (_localRenderer == null) {
      return _buildCameraOffPlaceholder();
    }

    final isCameraActive = _webRTCManager.isCameraOn &&
        _webRTCManager.localStream != null &&
        _webRTCManager.localStream!.getVideoTracks().isNotEmpty;

    if (!isCameraActive) {
      return _buildCameraOffPlaceholder();
    }

    // **PERBAIKAN: Pastikan renderer memiliki stream yang benar**
    if (_localRenderer!.srcObject != _webRTCManager.localStream) {
      _localRenderer!.srcObject = _webRTCManager.localStream;
    }

    return RTCVideoView(
      _localRenderer!,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      mirror: _webRTCManager.currentCamera == 'user',
    );
  }

  Widget _buildCameraOffPlaceholder() {
    return Container(
      color: Colors.black,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off, size: 32, color: Colors.white54),
          SizedBox(height: 8),
          Text('Camera Off', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }


  Widget _buildControls() {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: SafeArea(
        child: IgnorePointer(
          ignoring: false, // Tetap menerima input
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Debug controls
                  if (_isConnected)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildDebugButton(
                            icon: Icons.play_arrow,
                            label: 'Create Offer',
                            onPressed: () {
                              _webRTCManager.createOfferManually();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Manual offer created')),
                              );
                            },
                          ),
                          _buildDebugButton(
                            icon: Icons.refresh,
                            label: 'Reconnect',
                            onPressed: () {
                              _webRTCManager.reconnect();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Reconnecting...')),
                              );
                            },
                          ),
                          _buildDebugButton(
                            icon: Icons.replay,
                            label: 'Retry Conn',
                            onPressed: () {
                              _webRTCManager.retryConnections();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Retrying connections...')),
                              );
                            },
                          ),
                          _buildDebugButton(
                            icon: Icons.info,
                            label: 'Status',
                            onPressed: () {
                              _webRTCManager.checkConnectionStatus();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Check console for status')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
          
                  // Main controls
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildControlButton(
                          icon: _webRTCManager.isMuted ? Icons.mic_off : Icons.mic,
                          backgroundColor: _webRTCManager.isMuted ? Colors.red : Colors.white,
                          iconColor: _webRTCManager.isMuted ? Colors.white : Colors.black,
                          onPressed: () async {
                            await _webRTCManager.toggleMute();
                            if (mounted) {
                              setState(() {}); // **PERBAIKAN: Refresh UI setelah toggle**
                            }
                          },
                          tooltip: _webRTCManager.isMuted ? 'Unmute' : 'Mute',
                        ),
                        _buildControlButton(
                          icon: _webRTCManager.isCameraOn ? Icons.videocam : Icons.videocam_off,
                          backgroundColor: _webRTCManager.isCameraOn ? Colors.white : Colors.red,
                          iconColor: _webRTCManager.isCameraOn ? Colors.black : Colors.white,
                          onPressed: _webRTCManager.toggleCamera,
                          tooltip: _webRTCManager.isCameraOn ? 'Turn off camera' : 'Turn on camera',
                        ),
                        _buildControlButton(
                          icon: Icons.switch_camera,
                          backgroundColor: Colors.white,
                          iconColor: Colors.black,
                          onPressed: () async {
                            debugPrint('🔄 SWITCH CAMERA - Before:');
                            debugPrint('   - Local stream: ${_webRTCManager.localStream != null}');
                            debugPrint('   - Local renderer srcObject: ${_localRenderer?.srcObject != null}');
          
                            // **SIMPLE: Panggil switchCamera dan biarkan WebRTCManager handle sisanya**
                            await _webRTCManager.switchCamera();
          
                            // **UI AKAN OTOMATIS UPDATE via onLocalStream callback**
                            debugPrint('✅ Switch camera completed - waiting for UI update');
                          },
                          tooltip: 'Switch camera',
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
        ),
      ),
    );
  }

  Widget _buildDebugButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
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
        radius: 28,
        child: IconButton(
          icon: Icon(icon, size: 24),
          onPressed: onPressed,
          color: iconColor,
        ),
      ),
    );
  }

  void _endCall() {
    debugPrint('📞 Ending call...');
    _webRTCManager.disconnect();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    debugPrint('🧹 Disposing VideoCallScreen...');
    _isDisposed = true;

    // Dispose semua renderers
    _localRenderer?.dispose();
    _localRendererAlt?.dispose(); // **DISPOSE ALTERNATE RENDERER**

    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    _remoteRenderers.clear();

    _webRTCManager.dispose();

    super.dispose();
    debugPrint('✅ VideoCallScreen disposed');
  }
}

