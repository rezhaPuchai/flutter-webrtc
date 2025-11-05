import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:test_web_rtc/learn-rtc/rtc_manager.dart';

class RoomPage extends StatefulWidget {
  final String roomId;

  const RoomPage({super.key, required this.roomId});

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final RtcManager _webRTCManager = RtcManager();
  
  MediaStream? _localStream;
  
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _localRendererAlt;

  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  bool _isConnected = false;
  bool _isDisposed = false;
  bool _showControls = true;
  bool _permissionsChecked = false;

  Offset _localVideoPosition = const Offset(30, 100);
  bool _isDragging = false;

  double wLocalVideo = 150;
  double hLocalVideo = 220;
  bool isDefaultSizeLocalVideo = true;


  @override
  void initState() {
    debugPrint('PAGE: 🚀 Room ID: ${widget.roomId}');
    _initializeWithPermissions();
    super.initState();
  }

  @override
  void dispose() {
    debugPrint('PAGE: 🧹 Disposing RoomPage...');
    _isDisposed = true;

    // Dispose all local renderers
    _localRenderer?.dispose();
    _localRendererAlt?.dispose();

    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    _remoteRenderers.clear();

    _webRTCManager.disconnect();

    super.dispose();
    debugPrint('PAGE: ✅ RoomPage disposed');
  }

  Future<void> _initializeWithPermissions() async {
    try {
      await _initializeLocalRenderer();

      final cameraStatus = await Permission.camera.status;
      final micStatus = await Permission.microphone.status;

      debugPrint('PAGE: 📊 Permission status - Camera: $cameraStatus, Mic: $micStatus');

      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        debugPrint('PAGE: 🔄 Requesting permissions...');
        final statuses = await [Permission.camera, Permission.microphone].request();

        if (statuses[Permission.camera]?.isGranted == true &&
            statuses[Permission.microphone]?.isGranted == true) {
          debugPrint('PAGE: ✅ Permissions granted, next initializing WebRTC...');
          await Future.delayed(const Duration(milliseconds: 600));
          _initializeWebRTC();
        } else {
          debugPrint('PAGE: ❌ Permissions denied');
          _showPermissionError();
          return;
        }
      } else {
        debugPrint('PAGE: ✅ Permissions already granted, next initializing WebRTC...');
        _initializeWebRTC();
      }

      setState(() {
        _permissionsChecked = true;
      });

    } catch (e) {
      debugPrint('PAGE: ❌ _initializeWithPermissions error: $e');
      _showError('_initializeWithPermissions failed: $e');
    }
  }

  Future<void> _initializeLocalRenderer() async {
    try {
      _localRenderer = RTCVideoRenderer();
      await _localRenderer!.initialize();

      _localRendererAlt = RTCVideoRenderer();
      await _localRendererAlt!.initialize();
      debugPrint('PAGE: ✅ Local renderer initialized');
    } catch (e) {
      debugPrint('PAGE: ❌ Error _initializeLocalRenderer local renderer: $e');
      _showError(e.toString());
    }
  }

  void _initializeWebRTC() {
    debugPrint('PAGE: 🔧 _initializeWebRTC setting up WebRTC callbacks');

    debugPrint('PAGE: 🌐 Connecting to signaling server...');
    _webRTCManager.connect(
      "https://signaling-websocket.payuung.com",
      widget.roomId,
    );

    _webRTCManager.onConnected = () {
      debugPrint('PAGE: ✅ Connected to room');
      setState(() {
        _isConnected = true;
      });
    };

    _webRTCManager.onLocalStream = (stream) {
      debugPrint('PAGE: 📹 LOCAL STREAM UPDATED - Refreshing UI');

      setState(() {
        _localStream = stream;
        if (_localRenderer != null) {
          _localRenderer!.srcObject = stream;
          debugPrint('PAGE: ✅ Local renderer updated with new stream');
        }
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {});
          debugPrint('PAGE: ✅ Extra UI refresh completed');
        }
      });
    };

    _webRTCManager.onRemoteStream = (peerId, stream) async {
      debugPrint('PAGE: 📹 Remote stream ready for: $peerId');
      try {
        final renderer = RTCVideoRenderer();
        await renderer.initialize();

        if (mounted && !_isDisposed) {
          renderer.srcObject = stream;
          setState(() {
            _remoteRenderers[peerId] = renderer;
          });
          debugPrint('PAGE: ✅ Remote renderer created for: $peerId');
        } else {
          renderer.dispose();
        }
      } catch (e) {
        debugPrint('PAGE: ❌ Error creating remote renderer: $e');
      }
    };

    _webRTCManager.onPeerDisconnected = (peerId) {
      debugPrint('PAGE: 🔴 Peer disconnected: $peerId');
      setState(() {
        final renderer = _remoteRenderers[peerId];
        if (renderer != null) {
          renderer.dispose();
          _remoteRenderers.remove(peerId);
        }
      });
    };

    /*_webRTCManager.onError = (error) {
      debugPrint('PAGE: ❌ WebRTC Error: $error');
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
    };*/
    _webRTCManager.onError = (error) {
      debugPrint('PAGE: ❌ WebRTC Error: $error');

      // Handle native crash specifically
      if (error.contains('SIGABRT') || error.contains('DecodingQueue')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDisposed) {
            _showNativeCrashDialog();
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDisposed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        });
      }
    };

  }

  void _clickShowControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  Future<void> _muteMic() async {
    await _webRTCManager.toggleMute();
    if (mounted) {
      if(_webRTCManager.isProcessing == false){
        setState(() {});
      }
    }
  }

  void _disableCamera() {
    _webRTCManager.toggleCamera();
  }

  Future<void> _switchCamera() async {
    debugPrint('PAGE: 🔄 SWITCH CAMERA - Before:');
    debugPrint('PAGE: - Local stream: ${_webRTCManager.localStream != null}');
    debugPrint('PAGE: - Local renderer srcObject: ${_localRenderer?.srcObject != null}');

    await _webRTCManager.toggleSwitchCamera();

    debugPrint('PAGE: ✅ Switch camera completed - waiting for UI update');
  }

  void _endCall() {
    debugPrint('PAGE: 📞 Ending call......................');
    _webRTCManager.disconnect();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () {
          _clickShowControls();
        },
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            _buildRemoteVideos(),

            if (_localRenderer != null && _localStream != null)
              _buildDraggableLocalVideo(),

            if (!_isConnected)
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: Colors.orange.withOpacity(0.8),
                  child: Text(
                    'Connecting to room ${widget.roomId}...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

            if (_isConnected)
              Positioned(
                top: MediaQuery.of(context).padding.top + 30,
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

            _buildControls(),
          ],
        ),
      ),
    );
  }

  final Map<String, bool> _muted = {};

  /*Widget _buildRemoteVideos() {
    final remoteCount = _remoteRenderers.length;
    debugPrint('PAGE: ====== TOTAL VIDEO REMOTE TO SHOW $remoteCount ==========');

    if (remoteCount == 0) {
      return _buildWaitingScreen();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final availableWidth = constraints.maxWidth;

        if (remoteCount == 1) {
          return Stack(
            children: [
              RTCVideoView(
                _remoteRenderers.values.first,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    _remoteRenderers.keys.elementAt(0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      shadows: [
                        Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
                      ],
                    ),
                    maxLines: 3,
                  ),
                ),
              ),
            ],
          );
        }

        if (remoteCount == 2) {
          return Column(
            children: _remoteRenderers.entries.map((entry) {
              return Expanded(
                child: SizedBox(
                  width: availableWidth,
                  child: Stack(
                    children: [
                      RTCVideoView(
                        entry.value,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              shadows: [
                                Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
                              ],
                            ),
                            maxLines: 3,
                          ),
                        ),
                      ),
                    ],
                  )
                ),
              );
            }).toList(),
          );
        }

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

            return Stack(
              children: [
                Positioned.fill(
                  child: RTCVideoView(
                    renderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Text(
                    peerId,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      shadows: [
                        Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
                      ],
                    ),
                  ),
                ),
              ],
            );

          },
        );
      },
    );
  }*/

  Widget _buildRemoteVideos() {
    final remoteCount = _remoteRenderers.length;
    debugPrint('PAGE: ====== TOTAL VIDEO REMOTE TO SHOW $remoteCount ==========');

    if (remoteCount == 0) {
      return _buildWaitingScreen();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final availableWidth = constraints.maxWidth;

        // helper single tile builder
        Widget buildTile(String peerId, RTCVideoRenderer renderer, double w, double h) {
          final texId = renderer.textureId;
          final hasTexture = texId != null && renderer.srcObject != null;

          final videoWidget = hasTexture
              ? Texture(textureId: texId)
              : RTCVideoView(
            renderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          );

          final muteIcon = _muted[peerId] == true ? Icons.volume_off : Icons.volume_up;

          if (hasTexture) {
            // overlay button visible (texture rendered inside Flutter)
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(child: videoWidget),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          peerId,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        InkWell(
                          onTap: () => _toggleMute(peerId),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                            child: Icon(muteIcon, color: Colors.white, size: 18),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                // Positioned(
                //   right: 8,
                //   bottom: 8,
                //   child: InkWell(
                //     onTap: () => _toggleMute(peerId),
                //     borderRadius: BorderRadius.circular(24),
                //     child: Container(
                //       padding: const EdgeInsets.all(6),
                //       decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                //       child: Icon(muteIcon, color: Colors.white, size: 18),
                //     ),
                //   ),
                // ),
              ],
            );
          } else {
            // fallback: PlatformView likely on top -> show control bar under video
            return Column(
              children: [
                SizedBox(width: w, height: h, child: videoWidget),
                Container(
                  width: w,
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(peerId,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        onPressed: () => _toggleMute(peerId),
                        icon: Icon(muteIcon),
                        color: Colors.white,
                        splashRadius: 20,
                        iconSize: 22,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
        }

        if (remoteCount == 1) {
          final peerId = _remoteRenderers.keys.elementAt(0);
          final renderer = _remoteRenderers[peerId]!;
          return Stack(
            children: [
              RTCVideoView(
                renderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        peerId,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      InkWell(
                        onTap: () => _toggleMute(peerId),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                          child: Icon(_muted[peerId] == true ? Icons.volume_off : Icons.volume_up,
                              color: Colors.white, size: 22),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              // Positioned(
              //   right: 8,
              //   bottom: 8,
              //   child: InkWell(
              //     onTap: () => _toggleMute(peerId),
              //     borderRadius: BorderRadius.circular(24),
              //     child: Container(
              //       padding: const EdgeInsets.all(8),
              //       decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              //       child: Icon(_muted[peerId] == true ? Icons.volume_off : Icons.volume_up, color: Colors.white),
              //     ),
              //   ),
              // ),
            ],
          );
        }

        if (remoteCount == 2) {
          return Column(
            children: _remoteRenderers.entries.map((entry) {
              return Expanded(
                child: SizedBox(
                  width: availableWidth,
                  child: Stack(
                    children: [
                      RTCVideoView(
                        entry.value,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                entry.key,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              InkWell(
                                onTap: () => _toggleMute(entry.key),
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                                  child: Icon(_muted[entry.key] == true
                                      ? Icons.volume_off : Icons.volume_up,
                                      color: Colors.white, size: 22,),
                                ),
                              ),
                            ],
                          )
                        ),
                      ),
                      // Positioned(
                      //   right: 8,
                      //   bottom: 8,
                      //   child: InkWell(
                      //     onTap: () => _toggleMute(entry.key),
                      //     borderRadius: BorderRadius.circular(24),
                      //     child: Container(
                      //       padding: const EdgeInsets.all(8),
                      //       decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                      //       child: Icon(_muted[entry.key] == true ? Icons.volume_off : Icons.volume_up,
                      //           color: Colors.white),
                      //     ),
                      //   ),
                      // ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        }

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
            return buildTile(peerId, renderer, itemWidth, itemHeight);
          },
        );
      },
    );
  }

  Future<void> _toggleMute(String peerId) async {
    final renderer = _remoteRenderers[peerId];
    if (renderer == null) return;

    final stream = renderer.srcObject;
    final newMuted = !(_muted[peerId] ?? false);

    // jika tidak ada stream, hanya update status lokal
    if (stream == null) {
      setState(() => _muted[peerId] = newMuted);
      return;
    }

    try {
      for (var track in stream.getAudioTracks()) {
        track.enabled = !newMuted; // disable when muted
      }
    } catch (e) {
      debugPrint('toggleMute error for $peerId: $e');
    }

    setState(() => _muted[peerId] = newMuted);
  }


  Widget _buildWaitingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, size: 64, color: Colors.black54),
          const SizedBox(height: 16),
          const Text(
            'Waiting for other participants...',
            style: TextStyle(color: Colors.black54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (_isConnected)
            Text(
              'Share this room ID: ${widget.roomId}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildDraggableLocalVideo() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
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
            _localVideoPosition = Offset(
              _localVideoPosition.dx.clamp(0.0, screenWidth - wLocalVideo),
              _localVideoPosition.dy.clamp(0.0, (screenHeight - hLocalVideo)),
            );
          });
        },
        onPanEnd: (details) {
          setState(() {
            _isDragging = false;
          });
        },
        onTap: (){
          setState(() {
            if (isDefaultSizeLocalVideo) {
              wLocalVideo = screenWidth/1.6;
              hLocalVideo = screenHeight/2.2;
              isDefaultSizeLocalVideo = false;
            } else {
              wLocalVideo = 150;
              hLocalVideo = 220;
              isDefaultSizeLocalVideo = true;
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: wLocalVideo,
          height: hLocalVideo,
          decoration: BoxDecoration(
            border: Border.all(
              color: _isDragging ? Colors.blue : Colors.white,
              width: _isDragging ? 3 : 2,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
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

  Widget _buildLocalVideoContent() {
    if (_localRenderer == null) {
      return _buildCameraOffPlaceholder();
    }
    final isCameraActive = _webRTCManager.isCameraOn &&
        _webRTCManager.localStream != null &&
        _webRTCManager.localStream!.getVideoTracks().isNotEmpty;
    if (!isCameraActive) {
      return _buildCameraOffPlaceholder();
    }
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
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      bottom: _showControls ? 20 : -150, // geser ke bawah halus
      left: 0,
      right: 0,
      child: SafeArea(
        child: IgnorePointer(
          ignoring: !_showControls, // jangan bisa di-tap kalau sembunyi
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Manual offer created')),
                              );
                            },
                          ),
                          _buildDebugButton(
                            icon: Icons.refresh,
                            label: 'Reconnect',
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Reconnecting...')),
                              );
                            },
                          ),
                          _buildDebugButton(
                            icon: Icons.replay,
                            label: 'Retry Conn',
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Retrying connections...')),
                              );
                            },
                          ),
                          _buildDebugButton(
                            icon: Icons.info,
                            label: 'Status',
                            onPressed: () {
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black54.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildControlButton(
                          icon: _webRTCManager.isMuted ? Icons.mic_off : Icons.mic,
                          backgroundColor: _webRTCManager.isMuted ? Colors.red : Colors.white,
                          iconColor: _webRTCManager.isMuted ? Colors.white : Colors.black,
                          onPressed: _muteMic,
                          tooltip: _webRTCManager.isMuted ? 'Unmute' : 'Mute',
                        ),
                        _buildControlButton(
                          icon: _webRTCManager.isCameraOn ? Icons.videocam : Icons.videocam_off,
                          backgroundColor: _webRTCManager.isCameraOn ? Colors.white : Colors.red,
                          iconColor: _webRTCManager.isCameraOn ? Colors.black : Colors.white,
                          onPressed: _disableCamera,
                          tooltip: _webRTCManager.isCameraOn ? 'Turn off camera' : 'Turn on camera',
                        ),
                        _buildControlButton(
                          icon: Icons.switch_camera,
                          backgroundColor: Colors.white,
                          iconColor: Colors.black,
                          onPressed: _switchCamera,
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

  void _showNativeCrashDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Compatibility Issue'),
        content: const Text(
          'Detected video compatibility issues. Switching to compatibility mode for better stability.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
}
