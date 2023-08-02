import 'dart:core';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

/*
-Webrtc cung cấp các api để có thể tương tác được với các phần cứng của device như camera, micro...
-Cung cấp giải pháp biến những hình ảnh, âm thanh thu được từ camera, micro... thành media stream để hiển thị trên local và truyền đi
-Ví dụ này sẽ trình bày cách dùng các api của webrtc để tương tác với camera,micro, stream dữ liệu để show hình ảnh âm thanh dưới local
-Chua có phần connect các device với nhau.
 */

class GetUserMediaSample extends StatefulWidget {
  static String tag = 'get_usermedia_sample';

  @override
  _GetUserMediaSampleState createState() => _GetUserMediaSampleState();
}

class _GetUserMediaSampleState extends State<GetUserMediaSample> {
  MediaStream? _localStream;
  final _localRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  bool _isTorchOn = false;
  MediaRecorder? _mediaRecorder;
  bool get _isRec => _mediaRecorder != null;

  List<MediaDeviceInfo>? _mediaDevicesList;

  @override
  void initState() {
    super.initState();
    initRenderers();

    ///Media devices là các phần cứng liên quan đến media: cụ thể là camera trước, sau, micro, loa ngoài, loa trong(ear)
    ///Đăng ký lắng nghe sự kiện các media device thay đổi (eg: switch  loa ngoài loa trong).
    ///navigator.mediaDevices.enumerateDevices sẽ liệt kê ra các media devices.
    navigator.mediaDevices.ondevicechange = (event) async {
      print('++++++ ondevicechange ++++++');
      _mediaDevicesList = await navigator.mediaDevices.enumerateDevices();
      int x =0;
    };
  }


  @override
  void deactivate() {
    super.deactivate();
    if (_inCalling) {
      _hangUp();
    }
    _localRenderer.dispose();
    navigator.mediaDevices.ondevicechange = null;
  }

  void initRenderers() async {
    await _localRenderer.initialize();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  void _makeCall() async {
    final mediaConstraints = <String, dynamic>{
      'audio': false,
      'video': {
        'mandatory': {
          'minWidth':
              '640', // Provide your own width, height and frame rate here
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    try {
      ///Bật camer/micro... thu thập dự liệu, biến dữ liệu thành media stream
      ///stream này sẽ được sử dụng trong RTCVideoRenderer (_localRenderer) để hiển thị hình ảnh/âm thanh trên màn hình device
      var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      ///Lấy ra danh sách các media devices (được dùng cho chức năng hiển thị các thiết bị audio output - chuyển chế độ loa ngoài, loa trong)
      _mediaDevicesList = await navigator.mediaDevices.enumerateDevices();

      _localStream = stream;
      _localRenderer.srcObject = _localStream;

    } catch (e) {
      print(e.toString());
    }
    if (!mounted) return;

    setState(() {
      _inCalling = true;
    });
  }

  void _hangUp() async {
    try {
      if (kIsWeb) {
        _localStream?.getTracks().forEach((track) => track.stop());
      }
      await _localStream?.dispose();
      _localRenderer.srcObject = null;
      setState(() {
        _inCalling = false;
      });
    } catch (e) {
      print(e.toString());
    }
  }

  void _startRecording() async {
    if (_localStream == null) throw Exception('Stream is not initialized');
    if (Platform.isIOS) {
      print('Recording is not available on iOS');
      return;
    }
    // TODO(rostopira): request write storage permission
    final storagePath = await getExternalStorageDirectory();
    if (storagePath == null) throw Exception('Can\'t find storagePath');

    final filePath = storagePath.path + '/webrtc_sample/test.mp4';
    _mediaRecorder = MediaRecorder();
    setState(() {});

    ///video track và audiotrack là 1 1 phần của media stream, chứa dữ liệu video/audio...
    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    await _mediaRecorder!.start(
      filePath,
      videoTrack: videoTrack,
    );
  }

  void _stopRecording() async {
    await _mediaRecorder?.stop();
    setState(() {
      _mediaRecorder = null;
    });
  }

  void _toggleTorch() async {
    if (_localStream == null) throw Exception('Stream is not initialized');
    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    final has = await videoTrack.hasTorch();
    if (has) {
      print('[TORCH] Current camera supports torch mode');
      setState(() => _isTorchOn = !_isTorchOn);
      await videoTrack.setTorch(_isTorchOn);
      print('[TORCH] Torch state is now ${_isTorchOn ? 'on' : 'off'}');
    } else {
      print('[TORCH] Current camera does not support torch mode');
    }
  }

  void _toggleCamera() async {
    if (_localStream == null) throw Exception('Stream is not initialized');

    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    await Helper.switchCamera(videoTrack);
  }

  void _captureFrame() async {
    if (_localStream == null) throw Exception('Stream is not initialized');

    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    final frame = await videoTrack.captureFrame();
    await showDialog(
        context: context,
        builder: (context) => AlertDialog(
              content:
                  Image.memory(frame.asUint8List(), height: 720, width: 1280),
              actions: <Widget>[
                TextButton(
                  onPressed: Navigator.of(context, rootNavigator: true).pop,
                  child: Text('OK'),
                )
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('GetUserMedia API Test'),
        actions: _inCalling
            ? <Widget>[
                IconButton(
                  icon: Icon(_isTorchOn ? Icons.flash_off : Icons.flash_on),
                  onPressed: _toggleTorch,
                ),
                IconButton(
                  icon: Icon(Icons.switch_video),
                  onPressed: _toggleCamera,
                ),
                IconButton(
                  icon: Icon(Icons.camera),
                  onPressed: _captureFrame,
                ),
                IconButton(
                  icon: Icon(_isRec ? Icons.stop : Icons.fiber_manual_record),
                  onPressed: _isRec ? _stopRecording : _startRecording,
                ),
                PopupMenuButton<String>(
                  onSelected: _selectAudioOutput,
                  itemBuilder: (BuildContext context) {
                    if (_mediaDevicesList != null) {
                      return _mediaDevicesList!
                          .where((device) => device.kind == 'audiooutput')
                          .map((device) {
                        return PopupMenuItem<String>(
                          value: device.deviceId,
                          child: Text(device.label),
                        );
                      }).toList();
                    }
                    return [];
                  },
                ),
              ]
            : null,
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Center(
            child: Container(
              margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              decoration: BoxDecoration(color: Colors.black54),
              child: RTCVideoView(_localRenderer, mirror: true),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _inCalling ? _hangUp : _makeCall,
        tooltip: _inCalling ? 'Hangup' : 'Call',
        child: Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }

  void _selectAudioOutput(String deviceId) {
    _localRenderer.audioOutput(deviceId);
  }
}
