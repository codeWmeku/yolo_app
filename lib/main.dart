import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:translator/translator.dart';
import 'package:http/http.dart' as http;

late List<CameraDescription> cameras;

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Get available cameras
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Five in One', // Updated title
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        brightness: Brightness.light,
        textTheme: GoogleFonts.poppinsTextTheme(),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: HomeScreen(camera: camera),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final CameraDescription camera;

  const HomeScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this); // Updated to 6 tabs
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Five in One'), // Updated title
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          isScrollable: true, // Added to make tabs scrollable
          tabs: [
            Tab(icon: Icon(Icons.camera_alt), text: 'Camera'),
            Tab(icon: Icon(Icons.photo_library), text: 'Gallery'),
            Tab(icon: Icon(Icons.translate), text: 'Translator'),
            Tab(icon: Icon(Icons.perm_media), text: 'Multimedia'),
            Tab(icon: Icon(Icons.chat), text: 'Chatbot'),
            Tab(
              icon: Icon(Icons.search),
              text: 'Detection',
            ), // Added Detection tab
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          CameraScreen(camera: widget.camera),
          GalleryScreen(),
          TTSTranslatorScreen(),
          MultimediaScreen(),
          ChatbotScreen(),
          ObjectDetectionScreen(), // Added Object Detection screen
        ],
      ),
    );
  }
}

// Object Detection Service
class ObjectDetectionService {
  static const String baseUrl = 'http://192.168.100.35:8000';

  static Future<ObjectDetectionResult> detectObjects(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/detect-objects'),
      );
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      var streamedResponse = await request.send().timeout(
        Duration(seconds: 30),
      );
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return ObjectDetectionResult.fromJson(data);
      } else {
        throw Exception('Detection failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error detecting objects: $e');
    }
  }
}

// Data models for object detection
class ObjectDetectionResult {
  final bool success;
  final List<Detection> detections;
  final int totalObjects;
  final String? annotatedImageBase64;

  ObjectDetectionResult({
    required this.success,
    required this.detections,
    required this.totalObjects,
    this.annotatedImageBase64,
  });

  factory ObjectDetectionResult.fromJson(Map<String, dynamic> json) {
    return ObjectDetectionResult(
      success: json['success'] ?? false,
      detections:
          (json['detections'] as List?)
              ?.map((item) => Detection.fromJson(item))
              .toList() ??
          [],
      totalObjects: json['total_objects'] ?? 0,
      annotatedImageBase64: json['annotated_image'],
    );
  }
}

class Detection {
  final String className;
  final double confidence;
  final BoundingBox bbox;

  Detection({
    required this.className,
    required this.confidence,
    required this.bbox,
  });

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      className: json['class'] ?? '',
      confidence: (json['confidence'] ?? 0).toDouble(),
      bbox: BoundingBox.fromJson(json['bbox'] ?? {}),
    );
  }
}

class BoundingBox {
  final double x1, y1, x2, y2;

  BoundingBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x1: (json['x1'] ?? 0).toDouble(),
      y1: (json['y1'] ?? 0).toDouble(),
      x2: (json['x2'] ?? 0).toDouble(),
      y2: (json['y2'] ?? 0).toDouble(),
    );
  }
}

// Object Detection Screen
class ObjectDetectionScreen extends StatefulWidget {
  @override
  _ObjectDetectionScreenState createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen> {
  File? _selectedImage;
  ObjectDetectionResult? _detectionResult;
  bool _isDetecting = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImageAndDetect() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _detectionResult = null;
          _isDetecting = true;
        });

        // Perform object detection
        final result = await ObjectDetectionService.detectObjects(
          _selectedImage!,
        );

        setState(() {
          _detectionResult = result;
          _isDetecting = false;
        });

        if (result.totalObjects == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No objects detected in the image')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isDetecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _captureImageAndDetect() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _detectionResult = null;
          _isDetecting = true;
        });

        // Simple loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Processing image...')),
        );

        // Perform object detection
        final result = await ObjectDetectionService.detectObjects(
          _selectedImage!,
        );

        setState(() {
          _detectionResult = result;
          _isDetecting = false;
        });
      }
    } catch (e) {
      setState(() {
        _isDetecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildImageView() {
    // If no image or result yet
    if (_selectedImage == null) {
      return Container(
        height: 400,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'Take a photo to detect objects',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    // Show the annotated image from the server
    if (_detectionResult?.annotatedImageBase64 != null) {
      try {
        Uint8List bytes = base64Decode(_detectionResult!.annotatedImageBase64!);
        return Container(
          width: double.infinity,
          height: 400,
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      } catch (e) {
        return Container(
          height: 400,
          child: Center(child: Text('Error displaying image')),
        );
      }
    }

    // Fallback to original image
    return Container(
      width: double.infinity,
      height: 400,
      child: _isDetecting
          ? Center(child: CircularProgressIndicator())
          : Image.file(_selectedImage!, fit: BoxFit.contain),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Object Detection'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Main image view
          Expanded(
            child: _buildImageView(),
          ),
          
          // Simple controls at bottom
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isDetecting ? null : _captureImageAndDetect,
                  icon: Icon(Icons.camera_alt),
                  label: Text('Capture & Detect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isDetecting ? null : _pickImageAndDetect,
                  icon: Icon(Icons.photo_library),
                  label: Text('Select Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Simple detection count if available
          if (_detectionResult != null && _detectionResult!.detections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'Found ${_detectionResult!.totalObjects} object${_detectionResult!.totalObjects != 1 ? 's' : ''}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

// ... (Keep all your existing classes: CameraScreen, GalleryScreen, ImagePreviewScreen, etc.)

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isProcessing = false;
  String? _lastImagePath;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      // Ensure the camera is initialized
      await _initializeControllerFuture;

      setState(() {
        _isProcessing = true;
      });

      // Take the picture
      final image = await _controller.takePicture();

      // Save image to a permanent directory
      final directory = await getApplicationDocumentsDirectory();
      final filename = path.basename(image.path);
      final savedImage = await File(
        image.path,
      ).copy('${directory.path}/$filename');

      setState(() {
        _isProcessing = false;
        _lastImagePath = savedImage.path;
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Picture saved successfully!'),
          duration: Duration(seconds: 2),
        ),
      );

      // Navigate to preview
      if (_lastImagePath != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (context) => ImagePreviewScreen(imagePath: _lastImagePath!),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error taking picture: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(_controller),
                // UI elements overlay
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      color: Colors.black.withOpacity(0.4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (_lastImagePath != null)
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (context) => ImagePreviewScreen(
                                          imagePath: _lastImagePath!,
                                        ),
                                  ),
                                );
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  image: DecorationImage(
                                    image: FileImage(File(_lastImagePath!)),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            )
                          else
                            SizedBox(width: 50),
                          GestureDetector(
                            onTap: _isProcessing ? null : _takePicture,
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4,
                                ),
                              ),
                              child:
                                  _isProcessing
                                      ? CircularProgressIndicator(
                                        color: Colors.deepPurple,
                                      )
                                      : Container(),
                            ),
                          ),
                          SizedBox(width: 50),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

class GalleryScreen extends StatefulWidget {
  @override
  _GalleryScreenState createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _pickImage() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print(e);
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple.shade50, Colors.white],
          ),
        ),
        child: Center(
          child:
              _isLoading
                  ? CircularProgressIndicator()
                  : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_image != null)
                        Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                spreadRadius: 5,
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.file(_image!, fit: BoxFit.cover),
                          ),
                        )
                      else
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.image,
                            size: 100,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      SizedBox(height: 50),
                      ElevatedButton.icon(
                        onPressed: _pickImage,
                        icon: Icon(Icons.photo_library),
                        label: Text(
                          "Select Image from Gallery",
                          style: TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          minimumSize: Size(250, 50),
                        ),
                      ),
                      if (_image != null) ...[
                        SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (context) => ImagePreviewScreen(
                                      imagePath: _image!.path,
                                    ),
                              ),
                            );
                          },
                          icon: Icon(Icons.visibility),
                          label: Text(
                            "View Full Image",
                            style: TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            minimumSize: Size(250, 50),
                          ),
                        ),
                      ],
                    ],
                  ),
        ),
      ),
    );
  }
}

class ImagePreviewScreen extends StatelessWidget {
  final String imagePath;

  const ImagePreviewScreen({Key? key, required this.imagePath})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Image Preview'),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4,
          child: Image.file(File(imagePath), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class TTSTranslatorScreen extends StatefulWidget {
  @override
  _TTSTranslatorScreenState createState() => _TTSTranslatorScreenState();
}

class MultimediaScreen extends StatefulWidget {
  @override
  _MultimediaScreenState createState() => _MultimediaScreenState();
}

class ChatbotScreen extends StatefulWidget {
  @override
  _ChatbotScreenState createState() => _ChatbotScreenState();
}

class OllamaService {
  static const String baseUrl = 'http://192.168.100.35:8000';

  // Function to generate a response using your Python FastAPI server
  static Future<String> generateResponse(String prompt) async {
    try {
      // Using GET request with query parameter to match your Python server's /ask endpoint
      final response = await http.get(
        Uri.parse('$baseUrl/ask?q=${Uri.encodeComponent(prompt)}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        // Your Python server returns the response in the 'response' field
        return data['response'] ?? 'Sorry, I couldn\'t generate a response.';
      } else {
        print('Failed to get response: ${response.statusCode}');
        print('Response body: ${response.body}');
        return 'I\'m having trouble connecting to the server. Please check if your Python server is running on port 8000.';
      }
    } catch (e) {
      print('Error connecting to server: $e');
      return 'Error connecting to the server at 192.168.100.35:8000. Please make sure your Python FastAPI server is running.';
    }
  }
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    // Add welcome message
    _addBotMessage(
      'Welcome to Five in One! I\'m your virtual assistant powered by Mistral through your custom Python server. How can I help you today?',
    );
  }

  void _addMessage(String text, bool isUserMessage) {
    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUserMessage: isUserMessage,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  void _addBotMessage(String text) {
    _addMessage(text, false);
  }

  Future<void> _handleSubmitted(String text) async {
    _messageController.clear();
    if (text.trim().isEmpty) return;

    // Add user message
    _addMessage(text, true);

    // Show bot typing indicator
    setState(() {
      _isTyping = true;
    });

    try {
      // Get response from Ollama Mistral (with fallback to hardcoded responses)
      await _respondToMessage(text);
    } finally {
      // Ensure typing indicator is removed even if there's an error
      setState(() {
        _isTyping = false;
      });
    }
  }

  Future<void> _respondToMessage(String message) async {
    // Context about the app to help Ollama Mistral provide relevant responses
    final String appContext = """
    You are a helpful assistant for a mobile app called 'Five in One' that has these features:
    1. Camera tab - for taking photos
    2. Gallery tab - for viewing saved images
    3. Translator tab - for translating text between languages and using text-to-speech
    4. Multimedia tab - for uploading images and videos
    5. Chatbot tab - where users can ask questions and get help
    6. Detection tab - for object detection using AI
    
    Keep responses brief, friendly and helpful. Focus on providing information about the app's features.
    """;

    // Combine the context with the user's message
    final String promptWithContext =
        "$appContext\n\nUser: $message\n\nAssistant:";

    try {
      // First, try to use Ollama Mistral for a response
      String response = await OllamaService.generateResponse(promptWithContext);
      _addBotMessage(response);
    } catch (e) {
      print('Error using Ollama: $e');

      // Fallback to basic responses if Ollama fails
      final lowercaseMsg = message.toLowerCase();
      String fallbackResponse;

      // Simple response patterns as fallback
      if (lowercaseMsg.contains('hello') ||
          lowercaseMsg.contains('hi') ||
          lowercaseMsg.contains('hey')) {
        fallbackResponse = 'Hello there! How can I assist you today?';
      } else if (lowercaseMsg.contains('how are you')) {
        fallbackResponse =
            'I\'m just a virtual assistant, but I\'m functioning well! How about you?';
      } else if (lowercaseMsg.contains('name')) {
        fallbackResponse =
            'I\'m the AI Assistant, your friendly virtual helper!';
      } else if (lowercaseMsg.contains('feature') ||
          lowercaseMsg.contains('do')) {
        fallbackResponse =
            'I can help answer questions about our app features like camera, gallery, translation, multimedia, and object detection. What would you like to know?';
      } else if (lowercaseMsg.contains('camera')) {
        fallbackResponse =
            'Our camera feature allows you to take photos. You can access it from the Camera tab!';
      } else if (lowercaseMsg.contains('translate') ||
          lowercaseMsg.contains('translation')) {
        fallbackResponse =
            'Our translation feature supports multiple languages including Tagalog, Korean, Japanese, and more. Check the Translator tab!';
      } else if (lowercaseMsg.contains('image') ||
          lowercaseMsg.contains('photo')) {
        fallbackResponse =
            'You can view your photos in the Gallery tab, or upload new ones in the Multimedia tab.';
      } else if (lowercaseMsg.contains('video')) {
        fallbackResponse =
            'You can upload and manage videos in the Multimedia tab.';
      } else if (lowercaseMsg.contains('detect') ||
          lowercaseMsg.contains('object')) {
        fallbackResponse =
            'Our object detection feature can identify objects in your photos using AI. Check the Detection tab!';
      } else if (lowercaseMsg.contains('bye') ||
          lowercaseMsg.contains('goodbye') ||
          lowercaseMsg.contains('see you')) {
        fallbackResponse = 'Goodbye! Feel free to chat again if you need help.';
      } else if (lowercaseMsg.contains('thank')) {
        fallbackResponse = 'You\'re welcome! I\'m glad I could help.';
      } else {
        fallbackResponse =
            'I\'m still learning. Could you try asking something else about our app features?';
      }

      _addBotMessage(
        fallbackResponse +
            ' (Using fallback responses as Ollama connection failed)',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.grey.shade100),
              child:
                  _messages.isEmpty
                      ? Center(
                        child: Text(
                          'Start chatting!',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                      : ListView.builder(
                        reverse: true,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message =
                              _messages[_messages.length - 1 - index];
                          return _buildMessageWidget(message);
                        },
                      ),
            ),
          ),
          if (_isTyping)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.deepPurple,
                    child: Icon(Icons.smart_toy, color: Colors.white),
                    radius: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Typing...',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade300,
                  offset: Offset(0, -1),
                  blurRadius: 3,
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: _handleSubmitted,
                  ),
                ),
                SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: () => _handleSubmitted(_messageController.text),
                  child: Icon(Icons.send),
                  backgroundColor: Colors.deepPurple,
                  elevation: 0,
                  mini: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageWidget(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment:
            message.isUserMessage
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUserMessage) ...[
            CircleAvatar(
              backgroundColor: Colors.deepPurple,
              child: Icon(Icons.smart_toy, color: Colors.white),
              radius: 16,
            ),
            SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: message.isUserMessage ? Colors.deepPurple : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      color:
                          message.isUserMessage ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _formatTimestamp(message.timestamp),
                    style: TextStyle(
                      color:
                          message.isUserMessage
                              ? Colors.white.withOpacity(0.7)
                              : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (message.isUserMessage) ...[
            SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.teal,
              child: Icon(Icons.person, color: Colors.white),
              radius: 16,
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class ChatMessage {
  final String text;
  final bool isUserMessage;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUserMessage,
    required this.timestamp,
  });
}

class _MultimediaScreenState extends State<MultimediaScreen> {
  File? _selectedImage;
  File? _selectedVideo;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _pickImage() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _selectedVideo = null; // Reset video when image is selected
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print(e);
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickVideo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final XFile? pickedFile = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedVideo = File(pickedFile.path);
          _selectedImage = null; // Reset image when video is selected
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print(e);
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple.shade50, Colors.white],
          ),
        ),
        child:
            _isLoading
                ? Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: 20),
                      Text(
                        'Multimedia Upload',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildButton(
                            icon: Icons.image,
                            label: 'Upload Image',
                            onPressed: _pickImage,
                            color: Colors.blue,
                          ),
                          _buildButton(
                            icon: Icons.videocam,
                            label: 'Upload Video',
                            onPressed: _pickVideo,
                            color: Colors.red,
                          ),
                        ],
                      ),
                      SizedBox(height: 30),
                      if (_selectedImage != null) ..._buildImagePreview(),
                      if (_selectedVideo != null) ..._buildVideoInfo(),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  List<Widget> _buildImagePreview() {
    return [
      Text(
        'Selected Image',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      SizedBox(height: 10),
      Container(
        height: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              spreadRadius: 5,
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.file(_selectedImage!, fit: BoxFit.cover),
        ),
      ),
      SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              // Add future image upload functionality here
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Image upload functionality to be implemented'),
                ),
              );
            },
            icon: Icon(Icons.cloud_upload),
            label: Text('Upload to Cloud'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildVideoInfo() {
    return [
      Text(
        'Selected Video',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      SizedBox(height: 10),
      Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              spreadRadius: 5,
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Icon(Icons.videocam, size: 80, color: Colors.white54),
        ),
      ),
      SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              // Add video playback functionality here
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Video playback functionality to be implemented',
                  ),
                ),
              );
            },
            icon: Icon(Icons.play_arrow),
            label: Text('Play Video'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
          ElevatedButton.icon(
            onPressed: () {
              // Add future video upload functionality here
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Video upload functionality to be implemented'),
                ),
              );
            },
            icon: Icon(Icons.cloud_upload),
            label: Text('Upload to Cloud'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    ];
  }
}

class _TTSTranslatorScreenState extends State<TTSTranslatorScreen> {
  final TextEditingController _textController = TextEditingController();
  FlutterTts flutterTts = FlutterTts();
  final translator = GoogleTranslator();
  String translatedText = "";
  String selectedLanguage = 'tl'; // Default: Tagalog ('tl')

  // Function to translate text
  Future<void> translateText(String text) async {
    var translation = await translator.translate(text, to: selectedLanguage);
    setState(() {
      translatedText = translation.text;
    });
  }

  // Function to speak the original or translated text
  Future<void> speak(String text, String lang) async {
    await flutterTts.setLanguage(lang);
    await flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _textController,
              decoration: InputDecoration(labelText: 'Enter text'),
            ),
            SizedBox(height: 20),
            DropdownButton<String>(
              value: selectedLanguage,
              items: [
                DropdownMenuItem(value: 'tl', child: Text('Tagalog')),
                DropdownMenuItem(value: 'ko', child: Text('Korean')),
                DropdownMenuItem(value: 'ja', child: Text('Japanese')),
                DropdownMenuItem(value: 'zh-cn', child: Text('Chinese')),
                DropdownMenuItem(value: 'es', child: Text('Spanish')),
                DropdownMenuItem(value: 'fr', child: Text('French')),
                DropdownMenuItem(value: 'de', child: Text('German')),
              ],
              onChanged: (value) {
                setState(() {
                  selectedLanguage = value!;
                });
              },
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                String inputText = _textController.text;
                if (inputText.isNotEmpty) {
                  await translateText(inputText);
                }
              },
              child: Text('Translate'),
            ),
            SizedBox(height: 20),
            Text(
              translatedText.isNotEmpty
                  ? "Translated: $translatedText"
                  : "Translation will appear here",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    speak(_textController.text, 'en-US'); // Speak original
                  },
                  child: Text('Speak (English)'),
                ),
                ElevatedButton(
                  onPressed: () {
                    speak(translatedText, selectedLanguage); // Speak translated
                  },
                  child: Text('Speak (Translated)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
