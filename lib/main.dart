import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pro Camera App',
      theme: ThemeData.dark(),
      home: const PermissionsGate(),
    );
  }
}

class PermissionsGate extends StatefulWidget {
  const PermissionsGate({super.key});

  @override
  State<PermissionsGate> createState() => _PermissionsGateState();
}

class _PermissionsGateState extends State<PermissionsGate> {
  late Future<bool> _permissionsFuture;

  @override
  void initState() {
    super.initState();
    _permissionsFuture = _requestPermissions();
  }

  Future<bool> _requestPermissions() async {
    var cameraStatus = await Permission.camera.request();
    var microStatus = await Permission.microphone.request();
    return cameraStatus.isGranted && microStatus.isGranted;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _permissionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        } else if (snapshot.hasData && snapshot.data == true) {
          return const CameraScreenLoader();
        } else {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Camera and microphone permissions are required.'),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _permissionsFuture = _requestPermissions();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                  ElevatedButton(
                    onPressed: openAppSettings,
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}

class CameraScreenLoader extends StatelessWidget {
  const CameraScreenLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CameraDescription>>(
      future: availableCameras(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return CameraScreen(cameras: snapshot.data!);
        } else {
          return const Scaffold(body: Center(child: Text('No cameras found')));
        }
      },
    );
  }
}

enum CameraMode { photo, video }

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.cameras,
  });

  final List<CameraDescription> cameras;

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  int _selectedCameraIndex = 0;
  CameraMode _mode = CameraMode.photo;
  bool _isRecording = false;
  Timer? _timer;
  int _recordDuration = 0;
  FlashMode _flashMode = FlashMode.off;

  // Pro controls state
  bool _showProControls = false;
  double _minZoom = 1.0, _maxZoom = 1.0, _currentZoom = 1.0;
  double _minExposure = 0.0, _maxExposure = 0.0, _currentExposure = 0.0;
  WhiteBalancePreset _whiteBalancePreset = WhiteBalancePreset.auto;
  Offset? _focusPoint;
  Timer? _focusPointTimer;


  @override
  void initState() {
    super.initState();
    _initializeCamera(widget.cameras[_selectedCameraIndex]);
  }

  void _initializeCamera(CameraDescription cameraDescription) {
    _controller = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: true,
    );

    _initializeControllerFuture = _controller.initialize().then((_) {
      _controller.getMinZoomLevel().then((min) => _minZoom = min);
      _controller.getMaxZoomLevel().then((max) => _maxZoom = max);
      _controller.getMinExposureOffset().then((min) => _minExposure = min);
      _controller.getMaxExposureOffset().then((max) => _maxExposure = max);
      if (mounted) setState(() {});
    });

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    _focusPointTimer?.cancel();
    super.dispose();
  }

  void _onSwitchCameraPressed() {
    final newIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    setState(() {
      _selectedCameraIndex = newIndex;
    });
    _initializeCamera(widget.cameras[newIndex]);
  }

  void _onFlashModeButtonPressed() {
    final nextMode = FlashMode.values[(_flashMode.index + 1) % FlashMode.values.length];
    _controller.setFlashMode(nextMode);
    setState(() {
      _flashMode = nextMode;
    });
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off: return Icons.flash_off;
      case FlashMode.auto: return Icons.flash_auto;
      case FlashMode.always: return Icons.flash_on;
      case FlashMode.torch: return Icons.highlight;
    }
  }

  void _onCaptureButtonPressed() {
    if (_mode == CameraMode.photo) {
      _takePicture();
    } else {
      _isRecording ? _stopVideoRecording() : _startVideoRecording();
    }
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();
      if (!mounted) return;
      await GallerySaver.saveImage(image.path);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Picture saved!')));
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => DisplayPictureScreen(imagePath: image.path)));
    } catch (e) {
      print(e);
    }
  }

  Future<void> _startVideoRecording() async {
    setState(() { _isRecording = true; _recordDuration = 0; });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => setState(() => _recordDuration++));
    await _controller.startVideoRecording();
  }

  Future<void> _stopVideoRecording() async {
    _timer?.cancel();
    final file = await _controller.stopVideoRecording();
    setState(() { _isRecording = false; });
    await GallerySaver.saveVideo(file.path);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video saved!')));
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => VideoPlayerScreen(videoPath: file.path)));
  }

  void _onZoomChanged(double zoom) {
    setState(() => _currentZoom = zoom);
    _controller.setZoomLevel(zoom);
  }

  void _onExposureChanged(double exposure) {
    setState(() => _currentExposure = exposure);
    _controller.setExposureOffset(exposure);
  }

  void _onWhiteBalancePressed(WhiteBalancePreset preset) {
    setState(() => _whiteBalancePreset = preset);
    _controller.setWhiteBalancePreset(preset);
  }

  Future<void> _onTapToFocus(TapUpDetails details) async {
    if(!_controller.value.isInitialized || !_showProControls) return;
    final size = MediaQuery.of(context).size;
    final offset = Offset(details.localPosition.dx / size.width, details.localPosition.dy / size.height);
    await _controller.setFocusPoint(offset);
    await _controller.setFocusMode(FocusMode.auto);
    setState(() {
      _focusPoint = offset;
      _focusPointTimer?.cancel();
      _focusPointTimer = Timer(const Duration(seconds: 2), () => setState(() => _focusPoint = null));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pro Camera'),
        actions: [
          IconButton(
            icon: Icon(Icons.tune),
            onPressed: () => setState(() => _showProControls = !_showProControls),
          ),
          IconButton(icon: Icon(_getFlashIcon()), onPressed: _onFlashModeButtonPressed),
          IconButton(icon: const Icon(Icons.flip_camera_ios), onPressed: _onSwitchCameraPressed),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                GestureDetector(
                  onTapUp: _onTapToFocus,
                  child: CameraPreview(_controller)
                ),
                if (_focusPoint != null)
                  Positioned.fromRect(
                    rect: Rect.fromCenter(
                      center: Offset(_focusPoint!.dx * MediaQuery.of(context).size.width, _focusPoint!.dy * MediaQuery.of(context).size.height),
                      width: 80,
                      height: 80,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.yellow, width: 2),
                        borderRadius: BorderRadius.circular(40)
                      ),
                    ),
                  ),
                if (_isRecording)
                  Positioned(
                    top: 10, left: 10,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                      child: Text('${_recordDuration ~/ 60}:${(_recordDuration % 60).toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white, fontSize: 20)),
                    ),
                  ),
                Visibility(
                  visible: _showProControls,
                  child: Positioned(
                    left: 15, bottom: 150, top: 50,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Zoom", style: TextStyle(color: Colors.white, backgroundColor: Colors.black54)),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              value: _currentZoom, min: _minZoom, max: _maxZoom,
                              onChanged: _onZoomChanged,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Visibility(
                  visible: _showProControls,
                  child: Positioned(
                    right: 15, bottom: 150, top: 50,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("EV", style: TextStyle(color: Colors.white, backgroundColor: Colors.black54)),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              value: _currentExposure, min: _minExposure, max: _maxExposure,
                              onChanged: _onExposureChanged,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return BottomAppBar(
      color: Colors.transparent,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: _showProControls,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: WhiteBalancePreset.values.map((preset) =>
                  ChoiceChip(
                    label: Text(preset.toString().split('.').last),
                    selected: _whiteBalancePreset == preset,
                    onSelected: (_) => _onWhiteBalancePressed(preset),
                  )
                ).toList(),
              ),
            ),
          ),
          ToggleButtons(
            isSelected: [_mode == CameraMode.photo, _mode == CameraMode.video],
            onPressed: (index) => setState(() => _mode = index == 0 ? CameraMode.photo : CameraMode.video),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Photo')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Video')),
            ],
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _onCaptureButtonPressed,
            child: Icon(_isRecording ? Icons.stop : _mode == CameraMode.photo ? Icons.camera_alt : Icons.videocam),
          ),
        ],
      ),
    );
  }
}

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;
  const DisplayPictureScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      body: Image.file(File(imagePath)),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoPath;
  const VideoPlayerScreen({super.key, required this.videoPath});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Play Video')),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying ? _controller.pause() : _controller.play();
          });
        },
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}
