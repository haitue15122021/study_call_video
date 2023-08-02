import 'dart:core';
import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoSize {
  VideoSize(this.width, this.height);

  factory VideoSize.fromString(String size) {
    final parts = size.split('x');
    return VideoSize(int.parse(parts[0]), int.parse(parts[1]));
  }
  final int width;
  final int height;

  @override
  String toString() {
    return '$width x $height';
  }
}

/*
 * Đây là 1 demo nhỏ để mô phỏng 2 peer kết nối với nhau
 * Do đây chỉ là 1 demo nhỏ, 2 peer trên cùng 1 device ==> không cần dùng đến turn hay stun
 * Giả định rằng mặc nhiên peer2 đồng ý kết nối ngay ==> ko cần xử lý các trường hợp từ chối kết nối
 * 2 peer nằm cùng 1 device ==>không càn dùng socket để lắng nghe xem bên kia đồng ý không, kết thúc cuộc gọi không...
 */
class DeviceEnumerationSample extends StatefulWidget {
  static String tag = 'DeviceEnumerationSample';

  @override
  _DeviceEnumerationSampleState createState() =>
      _DeviceEnumerationSampleState();
}

class _DeviceEnumerationSampleState extends State<DeviceEnumerationSample> {
  MediaStream? _localStream;

  ///Sẽ chứa media stream data từ máy mình để hiển thị
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  ///Sẽ chứa media stream data từ máy khác được truyền đến để hiển thị
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;

  ///Khái niệm devices ở đây phải hiểu là các thiết bị videoinput,audioinput,audiooutput (camera/micro,loa) của device chứ ko phải cái máy điện thoại
  ///Load thông tin devices để biết thiết bị có support các phần cứng nào.
  List<MediaDeviceInfo> _devices = [];

  List<MediaDeviceInfo> get audioInputs =>
      _devices.where((device) => device.kind == 'audioinput').toList();

  List<MediaDeviceInfo> get audioOutputs =>
      _devices.where((device) => device.kind == 'audiooutput').toList();

  List<MediaDeviceInfo> get videoInputs =>
      _devices.where((device) => device.kind == 'videoinput').toList();

  ///Xác định camera trước hay sau.
  String? _selectedVideoInputId;


  String? _selectedAudioInputId;

  MediaDeviceInfo get selectedAudioInput => audioInputs.firstWhere(
      (device) => device.deviceId == _selectedVideoInputId,
      orElse: () => audioInputs.first);

  String? _selectedVideoFPS = '30';

  VideoSize _selectedVideoSize = VideoSize(1280, 720);

  @override
  void initState() {
    super.initState();

    initRenderers();
    loadDevices();
    navigator.mediaDevices.ondevicechange = (event) {
      loadDevices();
    };
  }

  @override
  void deactivate() {
    super.deactivate();
    _stop();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    navigator.mediaDevices.ondevicechange = null;
  }

  RTCPeerConnection? pc1;
  RTCPeerConnection? pc2;
  var senders = <RTCRtpSender>[];

  Future<void> initPCs() async {
    ///pc1 đại diện cho peer ở local
    ///pc2 đại diện cho peer ở máy remote, (nhưng đoạn code này hoàn toàn được chạy ở local, nó chỉ đại diện cho peer của máy remote).
    pc1 ??= await createPeerConnection({});
    pc2 ??= await createPeerConnection({});


    ///Khi peer 1 gọi hàm send track  thì peer 2 sẽ lắng nghe được
    ///Ở đây sẽ show luôn ra remote render do là 1 giả lập đơn giản.
    pc2?.onTrack = (event) {
      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
        setState(() {});
      }
    };
    ///Lắng nghe ConnectionState của peer2 2
    pc2?.onConnectionState = (state) {
      print('connectionState $state');
    };

    pc2?.onIceConnectionState = (state) {
      print('iceConnectionState $state');
    };

    await pc2?.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
    await pc2?.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));

    ///Khi peer 1 thu thập được 1 ICE Candidate ( framework sẽ sử dụng các máy chủ ICE đã cung cấp ) thì sẽ gửi cho pc2 và ngược lại
    ///ice candidate sẽ chứa các thông tin về địa chỉ IP, cổng mạng...
    /// Một peer có thể có nhiều địa chỉ IP trên các giao diện mạng khác nhau.ví dụ: địa chỉ IP nội bộ trong mạng LAN (Local Area Network) và địa chỉ IP công cộng bên ngoài NAT (Network Address Translation). Mỗi địa chỉ IP sẽ tạo ra một Local ICE candidate riêng biệt.
    /// Số lượng ICE candidate sẽ phụ thuộc vào nhiều yếu tố:Địa chỉ IP:,Giao thức mạng:,Cổng mạng,Điều kiện mạng
    /// Quá trình thu thập ICE candidates diễn ra theo hai giai đoạn chính:
    ///St1 Local ICE candidates : mỗi đối tác tự thu thập thông tin về địa chỉ IP và cổng mạng của mình
    ///St2: Remote ICE candidates : Sau khi có thông tin cục bộ, peer sẽ bắt đầu gửi thông tin này đến đối tác bên kia
    ///thông qua một phương thức trao đổi thông tin (signaling), ví dụ như WebSocket, HTTP hoặc qua một máy chủ trung gian.
    /// Đối tác kia nhận được thông tin và sử dụng nó như các ICE candidates từ xa để thêm vào danh sách các ứng viên ICE của mình
    /// Đây là 1 demo nhỏ, cả 2 peer trên 1 device nên ko cần websocket hay ,máy chủ nào.
    ///
    /// Quá trình thu thập ICE candidates kết thúc khi cả hai đối tác đã thu thập và trao đổi thông tin về tất cả các ICE candidates cục bộ và từ xa của họ thông qua signaling.
    /// Sau đó, họ sẽ sử dụng thông tin này để xác định các kết nối trực tiếp giữa họ bằng cách chọn một trong các ICE candidates có khả năng kết nối tốt nhất để truyền thông dữ liệu.

    ///ICE candidate có khả năng kết nối tốt nhất để truyền thông dữ liệu là ICE candidate mà có thể thiết lập kết nối trực tiếp giữa hai đối tác mà không cần sử dụng máy chủ trung gian (relay server) như TURN.
    ///Điều này thường xảy ra khi hai đối tác đang ở trong cùng một mạng LAN (Local Area Network) hoặc khi họ có thể truy cập trực tiếp vào địa chỉ IP công cộng của nhau thông qua các mạng công cộng.
    ///Nếu các ICE candidates không cho phép thiết lập kết nối trực tiếp, tức là hai đối tác không thể truyền dữ liệu trực tiếp với nhau, họ sẽ phải sử dụng một máy chủ trung gian như TURN để chuyển tiếp thông tin dữ liệu.
    ///==>Tùy vào điều kiện thực tế mà ICE nào sẽ được chọn để kết nối.
    pc1!.onIceCandidate = (candidate){
      pc2!.addCandidate(candidate);
    };
    pc2!.onIceCandidate = (candidate){
      pc1!.addCandidate(candidate);
    };
  }

  Future<void> _negotiate() async {

    ///offer do peer1 tạo ra ==> với peer 1 nó sẽ là local description
    ///ngược lại thì với peer2 nó sẽ là remote.
    var offer = await pc1?.createOffer();
    await pc1?.setLocalDescription(offer!);
    await pc2?.setRemoteDescription(offer!);

    ///answer do peer2 tạo ra ==> với peer 2 nó sẽ là local description
    ///ngược lại thì với peer1 nó sẽ là remote.
    var answer = await pc2?.createAnswer();
    await pc2?.setLocalDescription(answer!);
    await pc1?.setRemoteDescription(answer!);
  }

  Future<void> stopPCs() async {
    await pc1?.close();
    await pc2?.close();
    pc1 = null;
    pc2 = null;
  }

  Future<void> loadDevices() async {
    if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
      //Ask for runtime permissions if necessary.
      var status = await Permission.bluetooth.request();
      if (status.isPermanentlyDenied) {
        print('BLEpermdisabled');
      }

      status = await Permission.bluetoothConnect.request();
      if (status.isPermanentlyDenied) {
        print('ConnectPermdisabled');
      }
    }
    final devices = await navigator.mediaDevices.enumerateDevices();
    setState(() {
      _devices = devices;
    });
  }


  ///Thay đổi fps của video cũng sẽ ảnh hưởng đến người bên kia lên sẽ cần làm giống như khi thay đổi camera
  Future<void> _selectVideoFps(String fps) async {
    _selectedVideoFPS = fps;
    if (!_inCalling) {
      return;
    }
    await _selectVideoInput(_selectedVideoInputId);
    setState(() {});
  }


  ///Thay đổi  video size cũng sẽ ảnh hưởng đến người bên kia lên sẽ cần làm giống như khi thay đổi camera
  Future<void> _selectVideoSize(String size) async {
    _selectedVideoSize = VideoSize.fromString(size);
    if (!_inCalling) {
      return;
    }
    await _selectVideoInput(_selectedVideoInputId);
    setState(() {});
  }

  Future<void> _selectAudioInput(String? deviceId) async {
    _selectedAudioInputId = deviceId;
    if (!_inCalling) {
      return;
    }

    ///Khi thay đổi audioinput thì sẽ cần get lại mediastream  mới và send lại. vì ảnh hưởng đến bên remote
    ///trong medida stream sẽ có audio track và video track, ở đây thay đổi audio input thì sẽ chỉ replay audio track
    var newLocalStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        if (_selectedAudioInputId != null && kIsWeb)
          'deviceId': _selectedAudioInputId,
        if (_selectedAudioInputId != null && !kIsWeb)
          'optional': [
            {'sourceId': _selectedAudioInputId}
          ],
      },
      'video': false,
    });

    // replace track.
    var newTrack = newLocalStream.getAudioTracks().first;
    print('track.settings ' + newTrack.getSettings().toString());
    var sender =
        senders.firstWhereOrNull((sender) => sender.track?.kind == 'audio');
    await sender?.replaceTrack(newTrack);
  }

  Future<void> _selectAudioOutput(String? deviceId) async {
    if (!_inCalling) {
      return;
    }
    ///Thay đổi audio output(trên web) không ảnh hưởng đến bên kia nên ko cần cập nhật lại stream và send lại
    await _localRenderer.audioOutput(deviceId!);
  }

  var _speakerphoneOn = false;

  Future<void> _setSpeakerphoneOn() async {
    ///Thay đổi audio output(trên mobile) không ảnh hưởng đến bên kia nên ko cần cập nhật lại stream và send lại
    _speakerphoneOn = !_speakerphoneOn;
    await Helper.setSpeakerphoneOn(_speakerphoneOn);
    setState(() {});
  }

  ///Chọn cam trước/sau
  ///Đổi camera sẽ là 1 thay đổi ảnh hưởng đến cả bên mình lẫn đối tác nên cần đổi lại stream
  Future<void> _selectVideoInput(String? deviceId) async {
    _selectedVideoInputId = deviceId;
    if (!_inCalling) {
      return;
    }
    // 2) replace track.
    // stop old track.
    _localRenderer.srcObject = null;

    _localStream?.getTracks().forEach((track) async {
      await track.stop();
    });
    await _localStream?.dispose();

    var newLocalStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        if (_selectedVideoInputId != null && kIsWeb)
          'deviceId': _selectedVideoInputId,
        if (_selectedVideoInputId != null && !kIsWeb)
          'optional': [
            {'sourceId': _selectedVideoInputId}
          ],
        'width': _selectedVideoSize.width,
        'height': _selectedVideoSize.height,
        'frameRate': _selectedVideoFPS,
      },
    });
    _localStream = newLocalStream;
    _localRenderer.srcObject = _localStream;
    // replace track.
    var newTrack = _localStream?.getVideoTracks().first;
    print('track.settings ' + newTrack!.getSettings().toString());
    var sender =
        senders.firstWhereOrNull((sender) => sender.track?.kind == 'video');
    var params = sender!.parameters;
    print('params degradationPreference' +
        params.degradationPreference.toString());
    params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
    await sender.setParameters(params);
    await sender.replaceTrack(newTrack);
  }

  Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _start() async {
    try {

      ///ST1: lấy media stream data từ local để hiển thị ==> Hết ST1 này thì màn hình local sẽ show ra và hiển thị hình ảnh.
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          if (_selectedVideoInputId != null && kIsWeb)
            'deviceId': _selectedVideoInputId,
          if (_selectedVideoInputId != null && !kIsWeb)
            'optional': [
              {'sourceId': _selectedVideoInputId}
            ],
          'width': _selectedVideoSize.width,
          'height': _selectedVideoSize.height,
          'frameRate': _selectedVideoFPS,
        },
      });
      _localRenderer.srcObject = _localStream;
      _inCalling = true;


      ///ST2: Tạo 2 peer để tiến hành connect với nhau.
      await initPCs();

      ///ST3: Truyền các media stream data (track) từ local đi để remote có thể nhận được
      ///Chính vì peer này truyền đi thì hàm  pc2?.onTrack = (event)... ở trên mới có thể có cái mà lắng nghe.
      _localStream?.getTracks().forEach((track) async {
        var rtpSender = await pc1?.addTrack(track, _localStream!);
        print('track.settings ' + track.getSettings().toString());
        senders.add(rtpSender!);
      });

      ///St4: Quá trình gửi nhận offer và gửi nhận answer giữa 2 peer để connect.
      await _negotiate();

      ///Sau bước này thì đã có thể nhận được data remote và show lên.


      setState(() {});
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _stop() async {
    try {
      _localStream?.getTracks().forEach((track) async {
        await track.stop();
      });
      await _localStream?.dispose();
      _localStream = null;
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      senders.clear();
      _inCalling = false;
      await stopPCs();
      _speakerphoneOn = false;
      await Helper.setSpeakerphoneOn(_speakerphoneOn);
      setState(() {});
    } catch (e) {
      print(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      ///Phần appbar sẽ chứa các nút để thao tác với các thiết bị phần cứng như chọn micro,camera...
      appBar: AppBar(
        title: Text('DeviceEnumerationSample'),
        actions: [
          ///Chọn audio input (buildin micro or micro gắn ngoài)
          PopupMenuButton<String>(
            onSelected: _selectAudioInput,
            icon: Icon(Icons.settings_voice),
            itemBuilder: (BuildContext context) {
              return _devices
                  .where((device) => device.kind == 'audioinput')
                  .map((device) {
                return PopupMenuItem<String>(
                  value: device.deviceId,
                  child: Text(device.label),
                );
              }).toList();
            },
          ),

          ///Chọn audio output (loa ngoài/tai nghe,loa trong...)
          if (!WebRTC.platformIsMobile)
            PopupMenuButton<String>(
              onSelected: _selectAudioOutput,
              icon: Icon(Icons.volume_down_alt),
              itemBuilder: (BuildContext context) {
                return _devices
                    .where((device) => device.kind == 'audiooutput')
                    .map((device) {
                  return PopupMenuItem<String>(
                    value: device.deviceId,
                    child: Text(device.label),
                  );
                }).toList();
              },
            ),
          if (!kIsWeb && WebRTC.platformIsMobile)
            IconButton(
              disabledColor: Colors.grey,
              onPressed: _setSpeakerphoneOn,
              icon: Icon(
                  _speakerphoneOn ? Icons.speaker_phone : Icons.phone_android),
              tooltip: 'Switch SpeakerPhone',
            ),

          ///Chọn cam trước/sau
          PopupMenuButton<String>(
            onSelected: _selectVideoInput,
            icon: Icon(Icons.switch_camera),
            itemBuilder: (BuildContext context) {
              return _devices
                  .where((device) => device.kind == 'videoinput')
                  .map((device) {
                return PopupMenuItem<String>(
                  value: device.deviceId,
                  child: Text(device.label),
                );
              }).toList();
            },
          ),

          ///tHAY ĐỔI fps của video
          PopupMenuButton<String>(
            onSelected: _selectVideoFps,
            icon: Icon(Icons.menu),
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: _selectedVideoFPS,
                  child: Text('Select FPS ($_selectedVideoFPS)'),
                ),
                PopupMenuDivider(),
                ...['8', '15', '30', '60']
                    .map((fps) => PopupMenuItem<String>(
                          value: fps,
                          child: Text(fps),
                        ))
                    .toList()
              ];
            },
          ),

          ///Thay đổi video size
          PopupMenuButton<String>(
            onSelected: _selectVideoSize,
            icon: Icon(Icons.screenshot_monitor),
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: _selectedVideoSize.toString(),
                  child: Text('Select Video Size ($_selectedVideoSize)'),
                ),
                PopupMenuDivider(),
                ...['320x240', '640x480', '1280x720', '1920x1080']
                    .map((fps) => PopupMenuItem<String>(
                          value: fps,
                          child: Text(fps),
                        ))
                    .toList()
              ];
            },
          ),
        ],
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Center(
            child: Container(
                width: MediaQuery.of(context).size.width,
                color: Colors.white10,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                        decoration: BoxDecoration(color: Colors.black54),
                        child: RTCVideoView(_localRenderer),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                        decoration: BoxDecoration(color: Colors.black54),
                        child: RTCVideoView(_remoteRenderer),
                      ),
                    ),
                  ],
                )),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _inCalling ? _stop() : _start();
        },
        tooltip: _inCalling ? 'Hangup' : 'Call',
        child: Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }
}
