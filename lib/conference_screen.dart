import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:test_web_rtc/signaling_service.dart';
import 'package:test_web_rtc/second/webrtc_manager.dart';
/*

class ConferenceScreen extends StatefulWidget {
  final String roomId;

  const ConferenceScreen({Key? key, required this.roomId}) : super(key: key);

  @override
  _ConferenceScreenState createState() => _ConferenceScreenState();
}

class _ConferenceScreenState extends State<ConferenceScreen> {
  late SignalingService _signalingService;
  late WebRTCManager _webRTCManager;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _isConnected = false;
  bool _isCameraOn = true;
  bool _isMicOn = true;
  bool _isFrontCamera = true;

  @override
  void initState() {
    super.initState();
    _initializeWebRTC();
    _localRenderer.initialize();
  }

  Future<void> _initializeWebRTC() async {
    _signalingService = SignalingService();
    _webRTCManager = WebRTCManager(_signalingService);

    // Setup signaling callbacks
    _signalingService.onRoomJoined = (roomId) {
      setState(() {
        _isConnected = true;
      });
      _webRTCManager.createOffer();
    };

    _signalingService.onError = (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    };

    await _signalingService.initialize();
    await _webRTCManager.initialize();

    // Set local stream
    if (_webRTCManager.localStream != null) {
      _localRenderer.srcObject = _webRTCManager.localStream;
    }

    // Join room
    final success = await _signalingService.joinRoom(widget.roomId);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to join room')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room: ${widget.roomId}'),
        backgroundColor: Colors.blue[700],
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.videocam : Icons.videocam_off),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildVideoGrid(),
          ),
          _buildControlBar(),
        ],
      ),
    );
  }

  Widget _buildVideoGrid() {
    final remoteStreams = _webRTCManager.remoteStreams;
    final totalParticipants = 1 + remoteStreams.length;

    if (totalParticipants == 1) {
      return _buildLocalVideo();
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: totalParticipants <= 2 ? 1 : 2,
        childAspectRatio: 0.8,
      ),
      itemCount: totalParticipants,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildLocalVideo();
        } else {
          return _buildRemoteVideo(remoteStreams[index - 1]);
        }
      },
    );
  }

  Widget _buildLocalVideo() {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.black,
          ),
          child: RTCVideoView(_localRenderer),
        ),
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'You',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteVideo(RTCVideoRenderer renderer) {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black,
      ),
      child: RTCVideoView(renderer),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return CircleAvatar(
      backgroundColor: color,
      radius: 28,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }

  void _toggleMic() async {
    await _webRTCManager.toggleMute();
    setState(() {
      _isMicOn = !_isMicOn;
    });
  }

  void _toggleCamera() async {
    await _webRTCManager.toggleCamera().then((value){
      setState(() {
        _isCameraOn = !_isCameraOn;
      });
    }).catchError((e){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      throw e;
    });
  }

  void _switchCamera() async {
    await _webRTCManager.switchCamera();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

// Update build method untuk menampilkan status yang benar
  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.grey[200],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: _webRTCManager.isMuted ? Icons.mic_off : Icons.mic,
            color: _webRTCManager.isMuted ? Colors.red : Colors.blue,
            onPressed: _toggleMic,
          ),
          _buildControlButton(
            icon: _webRTCManager.isCameraOn ? Icons.videocam : Icons.videocam_off,
            color: _webRTCManager.isCameraOn ? Colors.blue : Colors.red,
            onPressed: _toggleCamera,
          ),
          _buildControlButton(
            icon: Icons.switch_video,
            color: Colors.blue,
            onPressed: _switchCamera,
          ),
          _buildControlButton(
            icon: Icons.call_end,
            color: Colors.red,
            onPressed: _endCall,
          ),
        ],
      ),
    );
  }

  void _endCall() {
    _signalingService.leaveRoom();
    _webRTCManager.dispose();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _signalingService.dispose();
    _webRTCManager.dispose();
    super.dispose();
  }
}*/
