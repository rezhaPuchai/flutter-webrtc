class SignalingMessage {
  final String type;
  final dynamic data;

  SignalingMessage({required this.type, this.data});

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    return SignalingMessage(
      type: json['type'],
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
    };
  }
}

class RoomInfo {
  final String roomId;
  final String? roomName;

  RoomInfo({required this.roomId, this.roomName});

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      roomId: json['roomId'],
      roomName: json['roomName'],
    );
  }
}