import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

enum InputSource { text, image, camera }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VerseCatchApp());
}

class VerseCatchApp extends StatelessWidget {
  const VerseCatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VerseCatch',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const VerseCatchHomePage(),
    );
  }
}

class VerseCatchHomePage extends StatefulWidget {
  const VerseCatchHomePage({super.key});

  @override
  State<VerseCatchHomePage> createState() => _VerseCatchHomePageState();
}

class _VerseCatchHomePageState extends State<VerseCatchHomePage> {
  final _store = VerseCaptureStore.instance;
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _textController = TextEditingController();

  InputSource _inputSource = InputSource.text;
  bool _processing = false;
  String? _lastImagePath;
  List<String> _references = const [];
  List<CaptureRecord> _history = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  void _onTextChanged() {
    final refs = extractVerseReferences(_textController.text);
    if (mounted) {
      setState(() => _references = refs);
    }
  }

  Future<void> _loadHistory() async {
    final history = await _store.recentCaptures();
    if (!mounted) return;
    setState(() => _history = history);
  }

  Future<void> _pickTextFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md'],
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      _textController.text = content;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    setState(() {
      _processing = true;
      _lastImagePath = path;
    });
    try {
      final text = await _runOcrOnImage(path);
      _textController.text = text;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _openCameraCapture() async {
    final imagePath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraCapturePage(),
        fullscreenDialog: true,
      ),
    );
    if (imagePath == null || !mounted) return;
    setState(() {
      _processing = true;
      _lastImagePath = imagePath;
    });
    try {
      final text = await _runOcrOnImage(imagePath);
      _textController.text = text;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<String> _runOcrOnImage(String imagePath) async {
    final preparedImage = await _prepareImageForOcr(imagePath);
    try {
      final inputImage = InputImage.fromFilePath(preparedImage.path);
      final recognized = await _textRecognizer.processImage(inputImage);
      return recognized.text.trim();
    } finally {
      if (preparedImage.temporary) {
        try {
          await File(preparedImage.path).delete();
        } on FileSystemException catch (e) {
          debugPrint('Unable to clean temporary OCR image: $e');
        }
      }
    }
  }

  Future<({String path, bool temporary})> _prepareImageForOcr(
    String sourcePath,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return (path: sourcePath, temporary: false);
    }

    const cropFactor = 0.9;
    final cropWidth = (decoded.width * cropFactor).round();
    final cropHeight = (decoded.height * cropFactor).round();
    final x = ((decoded.width - cropWidth) / 2).round();
    final y = ((decoded.height - cropHeight) / 2).round();

    final cropped = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: cropWidth,
      height: cropHeight,
    );
    final grayscale = img.grayscale(cropped);
    final resized = grayscale.width < 1200
        ? img.copyResize(grayscale, width: 1200)
        : grayscale;

    final directory = await getTemporaryDirectory();
    final outputPath = p.join(
      directory.path,
      'ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(outputPath).writeAsBytes(
      img.encodeJpg(resized, quality: 95),
      flush: true,
    );
    return (path: outputPath, temporary: true);
  }

  Future<void> _saveCapture() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await _store.insert(
      CaptureRecord(
        createdAt: DateTime.now(),
        imagePath: _lastImagePath ?? '',
        recognizedText: text,
        references: _references,
      ),
    );
    await _loadHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to history')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = _textController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VerseCatch'),
        actions: [
          if (hasText)
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save to history',
              onPressed: _processing ? null : _saveCapture,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SourceSelectorCard(
              selected: _inputSource,
              processing: _processing,
              lastImagePath:
                  _inputSource == InputSource.image ? _lastImagePath : null,
              onSourceChanged: (source) {
                setState(() => _inputSource = source);
              },
              onPickFile: _pickTextFile,
              onPickImage: _pickImage,
              onOpenCamera: _openCameraCapture,
            ),
            const SizedBox(height: 16),
            Text('Source text', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('source-text-field'),
              controller: _textController,
              maxLines: null,
              minLines: 4,
              decoration: InputDecoration(
                hintText: switch (_inputSource) {
                  InputSource.text => 'Paste or type text here…',
                  InputSource.image =>
                    'Pick an image — extracted text will appear here…',
                  InputSource.camera =>
                    'Open the camera — captured text will appear here…',
                },
                border: const OutlineInputBorder(),
                suffixIcon: hasText
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear text',
                        onPressed: () => _textController.clear(),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Text('Detected references', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (!hasText)
              const _EmptyState(
                message:
                    'Enter or load some text to detect verse references.',
              )
            else if (_references.isEmpty)
              const _EmptyState(message: 'No verse references detected.')
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _references
                        .map((ref) => Chip(label: Text(ref)))
                        .toList(),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('Recent scans', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              const _EmptyState(
                message: 'Your saved history will appear here.',
              )
            else
              ..._history.map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HistoryCard(record: record),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Source selector card
// ---------------------------------------------------------------------------

class _SourceSelectorCard extends StatelessWidget {
  const _SourceSelectorCard({
    required this.selected,
    required this.processing,
    required this.lastImagePath,
    required this.onSourceChanged,
    required this.onPickFile,
    required this.onPickImage,
    required this.onOpenCamera,
  });

  final InputSource selected;
  final bool processing;
  final String? lastImagePath;
  final ValueChanged<InputSource> onSourceChanged;
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final VoidCallback onOpenCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Input source', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            SegmentedButton<InputSource>(
              segments: const [
                ButtonSegment(
                  value: InputSource.text,
                  icon: Icon(Icons.text_fields),
                  label: Text('Text'),
                ),
                ButtonSegment(
                  value: InputSource.image,
                  icon: Icon(Icons.image_outlined),
                  label: Text('Image'),
                ),
                ButtonSegment(
                  value: InputSource.camera,
                  icon: Icon(Icons.camera_alt_outlined),
                  label: Text('Camera'),
                ),
              ],
              selected: {selected},
              onSelectionChanged: (s) => onSourceChanged(s.first),
            ),
            const SizedBox(height: 14),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    switch (selected) {
      case InputSource.text:
        return OutlinedButton.icon(
          onPressed: processing ? null : onPickFile,
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Load from file'),
        );

      case InputSource.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton.icon(
              onPressed: processing ? null : onPickImage,
              icon: processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.photo_library_outlined),
              label: Text(processing ? 'Processing…' : 'Pick image'),
            ),
            if (lastImagePath != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(lastImagePath!),
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        );

      case InputSource.camera:
        return FilledButton.icon(
          onPressed: processing ? null : onOpenCamera,
          icon: processing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.camera_alt_outlined),
          label: Text(processing ? 'Processing…' : 'Open camera'),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Camera capture page (full-screen dialog)
// ---------------------------------------------------------------------------

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  CameraController? _controller;
  bool _loading = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'No camera found on this device.';
            _loading = false;
          });
        }
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      await controller.initialize();

      try {
        await controller.setFlashMode(FlashMode.off);
      } on CameraException catch (e) {
        debugPrint('Flash mode unavailable: $e');
      }
      try {
        await controller.setFocusMode(FocusMode.auto);
      } on CameraException catch (e) {
        debugPrint('Focus mode unavailable: $e');
      }
      try {
        await controller.setExposureMode(ExposureMode.auto);
      } on CameraException catch (e) {
        debugPrint('Exposure mode unavailable: $e');
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Camera unavailable: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing ||
        controller.value.isTakingPicture) {
      return;
    }

    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Capture'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(child: CameraPreview(_controller!)),
                    Container(
                      color: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: GestureDetector(
                          onTap: _capturing ? null : _capture,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.15),
                              border:
                                  Border.all(color: Colors.white, width: 3),
                            ),
                            child: _capturing
                                ? const Padding(
                                    padding: EdgeInsets.all(18),
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.record});

  final CaptureRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatTimestamp(record.createdAt),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Text(
              record.recognizedText.isEmpty
                  ? 'No readable text captured.'
                  : record.recognizedText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            if (record.references.isEmpty)
              const Text('No references detected.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: record.references
                    .map((reference) => Chip(label: Text(reference)))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

class CaptureRecord {
  const CaptureRecord({
    required this.createdAt,
    required this.imagePath,
    required this.recognizedText,
    required this.references,
  });

  final DateTime createdAt;
  final String imagePath;
  final String recognizedText;
  final List<String> references;

  Map<String, Object?> toMap() {
    return {
      'created_at': createdAt.toIso8601String(),
      'image_path': imagePath,
      'recognized_text': recognizedText,
      'references_json': jsonEncode(references),
    };
  }

  factory CaptureRecord.fromMap(Map<String, Object?> map) {
    final referencesJson = map['references_json'] as String? ?? '[]';
    final decoded = jsonDecode(referencesJson);
    return CaptureRecord(
      createdAt: DateTime.parse(map['created_at'] as String),
      imagePath: map['image_path'] as String? ?? '',
      recognizedText: map['recognized_text'] as String? ?? '',
      references: decoded is List
          ? decoded.map((value) => value.toString()).toList(growable: false)
          : const [],
    );
  }
}

class VerseCaptureStore {
  VerseCaptureStore._();

  static final VerseCaptureStore instance = VerseCaptureStore._();

  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final directory = await getApplicationDocumentsDirectory();
    final databasePath = p.join(directory.path, 'versecatch.db');
    final database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE captures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            image_path TEXT NOT NULL,
            recognized_text TEXT NOT NULL,
            references_json TEXT NOT NULL
          )
        ''');
      },
    );

    _database = database;
    return database;
  }

  Future<void> insert(CaptureRecord record) async {
    final db = await _db;
    await db.insert(
      'captures',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CaptureRecord>> recentCaptures({int limit = 10}) async {
    final db = await _db;
    final rows = await db.query(
      'captures',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(CaptureRecord.fromMap).toList(growable: false);
  }
}

List<String> extractVerseReferences(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return const [];
  }

  final references = <String>{};
  final fullReferencePattern = RegExp(
    r'\b((?:[1-3]\s*)?[A-Za-zÁÉÍÓÚáéíóúÑñ\.]{1,20}(?:\s+[A-Za-zÁÉÍÓÚáéíóúÑñ\.]{1,20})?)\s+(\d{1,3})\s*(?::|\.|,|\s)\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?\b',
  );
  final continuationPattern = RegExp(
    r'^\s*[,;]\s*(\d{1,3})\s*(?::|\.|,|\s)\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?',
  );

  for (final match in fullReferencePattern.allMatches(normalized)) {
    final book = match.group(1)!;
    final chapter = match.group(2)!;
    final verse = match.group(3)!;
    final verseEnd = match.group(4);
    references.add(
      '$book $chapter:$verse${verseEnd == null ? '' : '-$verseEnd'}',
    );

    var cursor = match.end;
    while (cursor < normalized.length) {
      final continuation = continuationPattern.matchAsPrefix(
        normalized.substring(cursor),
      );
      if (continuation == null) {
        break;
      }

      final continuedChapter = continuation.group(1)!;
      final continuedVerse = continuation.group(2)!;
      final continuedVerseEnd = continuation.group(3);
      references.add(
        '$book $continuedChapter:$continuedVerse${continuedVerseEnd == null ? '' : '-$continuedVerseEnd'}',
      );
      cursor += continuation.end;
    }
  }

  return references.toList(growable: false);
}

String _formatTimestamp(DateTime dateTime) {
  final local = dateTime.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
