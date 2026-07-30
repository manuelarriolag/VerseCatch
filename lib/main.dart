import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum InputSource { text, image, camera }

typedef BibleTextLookup =
    Future<String?> Function(String reference, int bibleVersionId);

const bool kEnableHistoryFeature = false;
const bool kShowBanner = false;
const String kAppTitle = 'Verse Catch';
const String kAppVersionLabel = 'v1.0';
const String kNoBibleTextMessage =
    'Select a highlighted biblical citation to view biblical text.';
const String kLoadingBibleTextMessage = 'Loading biblical text...';
const String kIncludeBibleTextSettingKey = 'include_bible_text_in_output';
const String kExportDirectorySettingKey = 'export_directory_path';
const String kAppEnvironment = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'development',
);
const String kYouVersionApiBaseUrl = String.fromEnvironment(
  'YOUVERSION_API_BASE_URL',
  defaultValue: 'https://api.youversion.com',
);
const String kYouVersionAppKey = String.fromEnvironment('YOUVERSION_APP_KEY');
const int kYouVersionBibleVersionId = int.fromEnvironment(
  'YOUVERSION_BIBLE_VERSION_ID',
  defaultValue: 128,
);
const List<BibleVersionOption> kSupportedBibleVersions = [
  BibleVersionOption(
    id: 128,
    code: 'NVI-S',
    name: 'Nueva Versión Internacional 2025',
  ),
  BibleVersionOption(
    id: 103,
    code: 'NBLA',
    name: 'Nueva Biblia de las Américas',
  ),
  BibleVersionOption(
    id: 127,
    code: 'NTV',
    name: 'Nueva Traducción Viviente',
    enabled: false,
  ),
  BibleVersionOption(
    id: 149,
    code: 'RVR1960',
    name: 'Reina Valera 1960',
    enabled: false,
  ),
  BibleVersionOption(id: 3291, code: 'VBL', name: 'Biblia Libre'),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const VerseCatchApp());
}

String buildProcessingStatusLabel({
  required int current,
  required int total,
  required bool completed,
  required Duration elapsed,
}) {
  if (completed) {
    if (elapsed.inMinutes > 0) {
      final minutes = elapsed.inMinutes;
      final seconds = elapsed.inSeconds % 60;
      return seconds == 0
          ? 'Completado en ${minutes}m'
          : 'Completado en ${minutes}m ${seconds}s';
    }
    return 'Completado en ${elapsed.inSeconds}s';
  }
  if (total <= 1) {
    return 'Procesando…';
  }
  return '$current de $total';
}

String buildOutputContent({
  required String sourceText,
  required List<({String reference, int count})> groupedRefs,
  required bool includeBibleText,
  required Map<String, String> biblicalTexts,
  required String versionLabel,
}) {
  final buffer = StringBuffer();
  buffer.writeln('Texto escaneado');
  buffer.writeln();
  final trimmedSource = sourceText.trim();
  if (trimmedSource.isNotEmpty) {
    buffer.writeln(trimmedSource);
  } else {
    buffer.writeln('(Sin texto)');
  }
  buffer.writeln();

  if (groupedRefs.isEmpty) {
    buffer.writeln('No se encontraron citas bíblicas.');
    return buffer.toString().trimRight();
  }

  buffer.writeln('Citas bíblicas encontradas');
  buffer.writeln();
  for (final groupedRef in groupedRefs) {
    final reference = groupedRef.reference;
    final suffix = groupedRef.count > 1 ? ' (${groupedRef.count} veces)' : '';
    buffer.writeln('- $reference$suffix');
    if (!includeBibleText) {
      buffer.writeln();
      continue;
    }
    final bibleText = biblicalTexts[reference]?.trim();
    if (bibleText == null || bibleText.isEmpty) {
      buffer.writeln();
      continue;
    }
    buffer.writeln();
    buffer.writeln('  $versionLabel');
    buffer.writeln('  "$bibleText"');
    buffer.writeln();
  }

  return buffer.toString().trimRight();
}

String buildCitationsClipboardContent({
  required List<({String reference, int count})> groupedRefs,
  required bool includeBibleText,
  required Map<String, String> biblicalTexts,
  required String versionLabel,
}) {
  final buffer = StringBuffer();
  buffer.writeln('Citas bíblicas encontradas');
  buffer.writeln();

  if (groupedRefs.isEmpty) {
    buffer.writeln('(Sin citas bíblicas encontradas)');
    return buffer.toString().trimRight();
  }

  for (final groupedRef in groupedRefs) {
    final reference = groupedRef.reference;
    final suffix = groupedRef.count > 1 ? ' (${groupedRef.count} veces)' : '';
    buffer.writeln('- $reference$suffix');
    if (!includeBibleText) {
      buffer.writeln();
      continue;
    }
    final bibleText = biblicalTexts[reference]?.trim();
    if (bibleText == null || bibleText.isEmpty) {
      buffer.writeln();
      continue;
    }
    buffer.writeln();
    buffer.writeln('  $versionLabel');
    buffer.writeln('  "$bibleText"');
    buffer.writeln();
  }

  return buffer.toString().trimRight();
}

String buildScannedResultClipboardContent({
  required String sourceText,
  required List<({String reference, int count})> groupedRefs,
  required bool includeBibleText,
  required Map<String, String> biblicalTexts,
  required String versionLabel,
}) {
  final buffer = StringBuffer();
  buffer.writeln('Texto escaneado');
  buffer.writeln();

  final trimmedSource = sourceText.trim();
  if (trimmedSource.isNotEmpty) {
    buffer.writeln(trimmedSource);
  } else {
    buffer.writeln('(Sin texto)');
  }
  buffer.writeln();

  if (!includeBibleText || groupedRefs.isEmpty) {
    return buffer.toString().trimRight();
  }

  buffer.writeln('Texto bíblico');
  buffer.writeln();
  for (final groupedRef in groupedRefs) {
    final reference = groupedRef.reference;
    final bibleText = biblicalTexts[reference]?.trim();
    if (bibleText == null || bibleText.isEmpty) {
      continue;
    }
    buffer.writeln('- $reference');
    buffer.writeln();
    buffer.writeln('  $versionLabel');
    buffer.writeln('  "$bibleText"');
    buffer.writeln();
  }

  return buffer.toString().trimRight();
}

class VerseCatchApp extends StatelessWidget {
  const VerseCatchApp({
    super.key,
    this.bibleTextLookup = lookupBibleTextFromYouVersion,
  });

  final BibleTextLookup bibleTextLookup;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '$kAppTitle $kAppVersionLabel',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: WizardHomePage(bibleTextLookup: bibleTextLookup),
    );
  }
}

class VerseCatchHomePage extends StatefulWidget {
  const VerseCatchHomePage({super.key, required this.bibleTextLookup});

  final BibleTextLookup bibleTextLookup;

  @override
  State<VerseCatchHomePage> createState() => _VerseCatchHomePageState();
}

class _VerseCatchHomePageState extends State<VerseCatchHomePage> {
  final _store = VerseCaptureStore.instance;
  static const _ocrChannel = MethodChannel('versecatch/ocr');
  final _textController = HighlightTextEditingController();
  final _bibleTextController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _focusNode;

  InputSource _inputSource = InputSource.text;
  bool _processing = false;
  bool _isEditing = true;
  String? _lastImagePath;
  List<VerseMatch> _verseMatches = const [];
  String? _activeReference;
  String _lastProcessedText = '';
  List<CaptureRecord> _history = const [];
  bool _copiedFeedbackVisible = false;
  double _bodyRatio = 0.6;
  String? _selectedBibleText;
  String _biblePanelMessage = kNoBibleTextMessage;
  int _bibleLookupRequestId = 0;
  int _selectedBibleVersionId = kYouVersionBibleVersionId;
  bool _loadingBibleText = false;

  bool get _supportsCameraCapture =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  void _adjustBodyRatio({
    required double deltaDy,
    required double panelsHeight,
    required double minBodyRatio,
    required double maxBodyRatio,
    required double maxStep,
    required double sensitivity,
  }) {
    if (panelsHeight <= 0) return;
    final ratioDelta = ((deltaDy / panelsHeight) * sensitivity).clamp(
      -maxStep,
      maxStep,
    );
    final nextRatio = (_bodyRatio + ratioDelta).clamp(
      minBodyRatio,
      maxBodyRatio,
    );
    if (nextRatio == _bodyRatio) return;
    setState(() {
      _bodyRatio = nextRatio;
    });
  }

  int _fallbackBibleVersionId() {
    return kSupportedBibleVersions
        .firstWhere(
          (version) => version.enabled,
          orElse: () => kSupportedBibleVersions.first,
        )
        .id;
  }

  bool _isVersionEnabled(int versionId) {
    return kSupportedBibleVersions.any(
      (version) => version.id == versionId && version.enabled,
    );
  }

  BibleVersionOption _selectedBibleVersionOption() {
    return kSupportedBibleVersions.firstWhere(
      (version) => version.id == _selectedBibleVersionId,
      orElse: () => kSupportedBibleVersions.first,
    );
  }

  @override
  void initState() {
    super.initState();
    if (!_isVersionEnabled(_selectedBibleVersionId)) {
      _selectedBibleVersionId = _fallbackBibleVersionId();
    }
    _loadHistory();
    _loadBibleVersionPreference();
    _textController.addListener(_onControllerChanged);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _syncBibleText();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    _bibleTextController.dispose();
    _textController.removeListener(_onControllerChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final text = _textController.text;
    // Guard against re-entrancy from notifyListeners() inside highlights setter.
    if (text == _lastProcessedText) return;
    _lastProcessedText = text;

    final matches = extractVerseMatches(text);
    setState(() {
      _verseMatches = matches;
      _activeReference = null;
      // If text is cleared, go back to edit mode.
      if (matches.isEmpty) _isEditing = true;
    });
    _textController.highlights = _buildHighlights();
    _syncBibleText();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _verseMatches.isNotEmpty) {
      setState(() => _isEditing = false);
    }
  }

  void _switchToEditMode() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _resetAll() {
    _focusNode.unfocus();
    _textController.clear();
    setState(() {
      _verseMatches = const [];
      _activeReference = null;
      _isEditing = true;
      _lastImagePath = null;
      _copiedFeedbackVisible = false;
    });
    _textController.highlights = const [];
    _syncBibleText();
  }

  void _changeSource(InputSource source) {
    if (source == _inputSource) return;
    _focusNode.unfocus();
    _textController.clear();
    setState(() {
      _inputSource = source;
      _verseMatches = const [];
      _activeReference = null;
      _isEditing = true;
      _lastImagePath = null;
      _copiedFeedbackVisible = false;
    });
    _textController.highlights = const [];
    _syncBibleText();
  }

  List<({int start, int end, Color color})> _buildHighlights() {
    return _verseMatches
        .map(
          (vm) => (
            start: vm.start,
            end: vm.end,
            color: vm.reference == _activeReference
                ? _kMagenta
                : _kHighlightBlue,
          ),
        )
        .toList();
  }

  void _onReferenceTap(String reference) {
    final isSelectingSameReference = _activeReference == reference;
    setState(() {
      _activeReference = isSelectingSameReference ? null : reference;
    });
    _textController.highlights = _buildHighlights();
    _syncBibleText();
  }

  String? _getSelectedBibleText() {
    return _selectedBibleText;
  }

  void _setBiblePanel({required String message, String? bibleText}) {
    final trimmedText = bibleText?.trim();
    final selectedText = (trimmedText == null || trimmedText.isEmpty)
        ? null
        : trimmedText;
    final textToShow = selectedText ?? message;
    final mustUpdateState =
        _selectedBibleText != selectedText || _biblePanelMessage != message;
    final mustUpdateController = _bibleTextController.text != textToShow;
    if (!mustUpdateState && !mustUpdateController) return;

    setState(() {
      _selectedBibleText = selectedText;
      _biblePanelMessage = message;
      if (mustUpdateController) {
        _bibleTextController.value = TextEditingValue(
          text: textToShow,
          selection: const TextSelection.collapsed(offset: 0),
        );
      }
    });
  }

  Future<void> _syncBibleText() async {
    final activeReference = _activeReference;
    if (activeReference == null) {
      _bibleLookupRequestId++;
      if (_loadingBibleText) {
        setState(() => _loadingBibleText = false);
      }
      _setBiblePanel(message: kNoBibleTextMessage);
      return;
    }

    final requestId = ++_bibleLookupRequestId;
    if (!_loadingBibleText) {
      setState(() => _loadingBibleText = true);
    }
    _setBiblePanel(message: kLoadingBibleTextMessage);

    try {
      final bibleText = await widget.bibleTextLookup(
        activeReference,
        _selectedBibleVersionId,
      );
      if (!mounted || requestId != _bibleLookupRequestId) return;
      if (bibleText == null || bibleText.trim().isEmpty) {
        _setBiblePanel(message: 'No biblical text found for $activeReference.');
        return;
      }
      _setBiblePanel(message: kNoBibleTextMessage, bibleText: bibleText);
    } on YouVersionConfigurationException catch (error) {
      if (!mounted || requestId != _bibleLookupRequestId) return;
      _setBiblePanel(message: error.message);
    } on YouVersionApiException catch (error) {
      if (!mounted || requestId != _bibleLookupRequestId) return;
      _setBiblePanel(message: error.message);
    } on SocketException catch (error) {
      if (!mounted || requestId != _bibleLookupRequestId) return;
      _setBiblePanel(
        message: 'Network error while loading biblical text: $error',
      );
    } on FormatException catch (error) {
      if (!mounted || requestId != _bibleLookupRequestId) return;
      _setBiblePanel(
        message: 'Invalid response from biblical text API: $error',
      );
    } finally {
      if (mounted && requestId == _bibleLookupRequestId && _loadingBibleText) {
        setState(() => _loadingBibleText = false);
      }
    }
  }

  Future<void> _copySelectedBibleText() async {
    final referenceText = _activeReference;
    final bibleText = _getSelectedBibleText();
    if (referenceText == null || bibleText == null || bibleText.isEmpty) return;

    final versionCode = _selectedBibleVersionOption().code;
    final clipboardText = '$referenceText ($versionCode)\n"$bibleText"';
    await Clipboard.setData(ClipboardData(text: clipboardText));
    if (!mounted) return;

    setState(() => _copiedFeedbackVisible = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() => _copiedFeedbackVisible = false);
  }

  String _formatOcrError(Object error) {
    if (error is PlatformException) {
      final details = error.details;
      final detailsText = details == null ? '' : '\nDetails: $details';
      return 'Code: ${error.code}\nMessage: ${error.message ?? 'No message'}$detailsText';
    }
    return error.toString();
  }

  Future<void> _showOcrError(Object error) async {
    if (!mounted) return;
    final message = _formatOcrError(error);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('OCR failed'),
          content: SelectableText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadHistory() async {
    final history = await _store.recentCaptures();
    if (!mounted) return;
    setState(() => _history = history);
  }

  Future<void> _loadBibleVersionPreference() async {
    final persistedVersionId = await _store.selectedBibleVersionId();
    if (!mounted || persistedVersionId == null) return;
    final supportedVersion = kSupportedBibleVersions.any(
      (version) => version.id == persistedVersionId,
    );
    if (!supportedVersion) return;

    final versionToUse = _isVersionEnabled(persistedVersionId)
        ? persistedVersionId
        : _fallbackBibleVersionId();
    if (versionToUse == _selectedBibleVersionId) return;

    setState(() => _selectedBibleVersionId = versionToUse);
    await _store.setSelectedBibleVersionId(versionToUse);
    await _syncBibleText();
  }

  Future<void> _onBibleVersionChanged(int? selectedVersionId) async {
    if (selectedVersionId == null) return;
    if (!_isVersionEnabled(selectedVersionId)) return;
    if (_selectedBibleVersionId == selectedVersionId) return;
    setState(() => _selectedBibleVersionId = selectedVersionId);
    await _store.setSelectedBibleVersionId(selectedVersionId);
    await _syncBibleText();
  }

  Future<void> _pickTextFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (p.extension(path).toLowerCase() != '.txt') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a .txt file')),
        );
      }
      return;
    }
    try {
      final content = await File(path).readAsString();
      _textController.text = content;
      if (mounted && _verseMatches.isNotEmpty) {
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not read file: $e')));
      }
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
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
      if (mounted && _verseMatches.isNotEmpty) {
        setState(() => _isEditing = false);
      }
    } catch (e, st) {
      debugPrint('OCR failed while picking image: $e\n$st');
      await _showOcrError(e);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _openCameraCapture() async {
    if (!_supportsCameraCapture) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera capture is currently supported on iOS and Android only.',
            ),
          ),
        );
      }
      return;
    }
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
      if (mounted && _verseMatches.isNotEmpty) {
        setState(() => _isEditing = false);
      }
    } catch (e, st) {
      debugPrint('OCR failed after camera capture: $e\n$st');
      await _showOcrError(e);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<String> _runOcrOnImage(String imagePath) async {
    final preparedImage = await _prepareImageForOcr(imagePath);
    try {
      if (!(Platform.isMacOS || Platform.isIOS)) {
        return '';
      }

      final result = await _ocrChannel.invokeMethod<String>(
        'recognizeTextFromPath',
        {'path': preparedImage.path},
      );
      return result?.trim() ?? '';
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
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final outputPath = p.join(
      directory.path,
      'ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(
      outputPath,
    ).writeAsBytes(img.encodeJpg(resized, quality: 95), flush: true);
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
        references: _verseMatches.map((vm) => vm.reference).toSet().toList(),
      ),
    );
    await _loadHistory();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to history')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = _textController.text.isNotEmpty;
    final detectedReferenceCount = _verseMatches
        .map((vm) => vm.reference)
        .toSet()
        .length;
    final canDone = _isEditing && _verseMatches.isNotEmpty;
    final canEdit = !_isEditing;
    final immersiveEditMode = _isEditing && _verseMatches.isNotEmpty;
    final headerVisible = !immersiveEditMode;
    final footerVisible =
        !immersiveEditMode &&
        _textController.text.trim().isNotEmpty &&
        _activeReference != null;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const dividerHeight = 8.0;
                const minBodyRatio = 0.35;
                const maxBodyRatio = 0.8;
                final resizeHandleHeight = dividerHeight + 16.0;
                final headerHeight = headerVisible
                    ? (kShowBanner
                          ? (constraints.maxHeight * 0.42).clamp(280.0, 360.0)
                          : (constraints.maxHeight * 0.36).clamp(248.0, 320.0))
                    : 0.0;
                final contentHeight =
                    (constraints.maxHeight -
                            headerHeight -
                            (headerVisible ? 16.0 : 0.0))
                        .clamp(0.0, double.infinity);
                final panelsHeight = (contentHeight - dividerHeight).clamp(
                  0.0,
                  double.infinity,
                );
                const defaultBodyMinHeight = 240.0;
                const defaultFooterMinHeight = 180.0;
                const compactBodyMinFloor = 120.0;
                const compactFooterMinFloor = 96.0;

                final minHeightsScale = panelsHeight <= 0
                    ? 0.0
                    : (panelsHeight /
                              (defaultBodyMinHeight + defaultFooterMinHeight))
                          .clamp(0.0, 1.0);
                final bodyMinHeight = (defaultBodyMinHeight * minHeightsScale)
                    .clamp(compactBodyMinFloor, defaultBodyMinHeight);
                final footerMinHeight =
                    (defaultFooterMinHeight * minHeightsScale).clamp(
                      compactFooterMinFloor,
                      defaultFooterMinHeight,
                    );
                var effectiveBodyMinHeight = bodyMinHeight.toDouble();
                var effectiveFooterMinHeight = footerMinHeight.toDouble();
                final minimumPanelsHeight =
                    effectiveBodyMinHeight + effectiveFooterMinHeight;
                if (footerVisible &&
                    panelsHeight > 0 &&
                    minimumPanelsHeight > panelsHeight) {
                  final bodyShare =
                      effectiveBodyMinHeight / minimumPanelsHeight;
                  effectiveBodyMinHeight = panelsHeight * bodyShare;
                  effectiveFooterMinHeight =
                      panelsHeight - effectiveBodyMinHeight;
                }
                final bodyMaxHeight = (panelsHeight - effectiveFooterMinHeight)
                    .clamp(0.0, double.infinity);
                final bodyLowerBound = effectiveBodyMinHeight.clamp(
                  0.0,
                  bodyMaxHeight,
                );

                final bodyHeight = footerVisible
                    ? (panelsHeight * _bodyRatio).clamp(
                        bodyLowerBound,
                        bodyMaxHeight,
                      )
                    : contentHeight.clamp(compactBodyMinFloor, double.infinity);
                final footerHeight = footerVisible
                    ? (panelsHeight - bodyHeight).clamp(0.0, double.infinity)
                    : 0.0;
                final hasRealBibleText =
                    (_selectedBibleText?.isNotEmpty ?? false);
                final selectedBibleVersion = _selectedBibleVersionOption();
                final showBibleVersionName = constraints.maxWidth >= 430;

                return Column(
                  children: [
                    if (headerVisible)
                      SizedBox(
                        height: headerHeight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Verse Catch',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const Spacer(),
                                  if (kEnableHistoryFeature && hasText)
                                    IconButton(
                                      icon: const Icon(Icons.save_outlined),
                                      tooltip: 'Save to history',
                                      onPressed: _processing
                                          ? null
                                          : _saveCapture,
                                    ),
                                  IconButton(
                                    key: const ValueKey('reset-button'),
                                    icon: const Icon(
                                      Icons.restart_alt_outlined,
                                    ),
                                    tooltip: 'Start over',
                                    onPressed: _resetAll,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (kShowBanner) ...[
                                const _BannerImage(),
                                const SizedBox(height: 10),
                              ],
                              _SourceSelectorCard(
                                selected: _inputSource,
                                processing: _processing,
                                lastImagePath: _lastImagePath,
                                compactVertical: constraints.maxHeight < 760,
                                cameraSupported: _supportsCameraCapture,
                                onSourceChanged: _changeSource,
                                onPickFile: _pickTextFile,
                                onPickImage: _pickImage,
                                onOpenCamera: _openCameraCapture,
                              ),
                            ],
                          ),
                        ),
                      ),
                    SizedBox(
                      height: bodyHeight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        'Source text',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '($detectedReferenceCount)',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: canEdit ? _switchToEditMode : null,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Edit'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  key: const ValueKey('done-editing-button'),
                                  onPressed: canDone
                                      ? () {
                                          _focusNode.unfocus();
                                          setState(() => _isEditing = false);
                                        }
                                      : null,
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('Done'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(child: _buildBodyEditor(theme)),
                          ],
                        ),
                      ),
                    ),
                    if (footerVisible) ...[
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: Listener(
                          onPointerSignal: (event) {
                            if (event is! PointerScrollEvent) return;
                            _adjustBodyRatio(
                              deltaDy: event.scrollDelta.dy,
                              panelsHeight: panelsHeight,
                              minBodyRatio: minBodyRatio,
                              maxBodyRatio: maxBodyRatio,
                              maxStep: 0.1,
                              sensitivity: 0.9,
                            );
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragUpdate: (details) {
                              _adjustBodyRatio(
                                deltaDy: details.delta.dy,
                                panelsHeight: panelsHeight,
                                minBodyRatio: minBodyRatio,
                                maxBodyRatio: maxBodyRatio,
                                maxStep: _isDesktopPlatform ? 0.12 : 0.08,
                                sensitivity: _isDesktopPlatform ? 1.4 : 1.0,
                              );
                            },
                            onDoubleTap: () {
                              setState(() => _bodyRatio = 0.6);
                            },
                            child: SizedBox(
                              key: const ValueKey('footer-resize-handle'),
                              height: resizeHandleHeight,
                              child: Center(
                                child: Container(
                                  width: 72,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.outlineVariant,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: footerHeight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  if (_activeReference != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      _activeReference!,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            color: _kMagenta,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      key: ValueKey(
                                        'bible-version-selector-$_selectedBibleVersionId',
                                      ),
                                      value: _selectedBibleVersionId,
                                      isDense: true,
                                      style: theme.textTheme.titleMedium,
                                      items: kSupportedBibleVersions
                                          .where((version) => version.enabled)
                                          .map(
                                            (version) => DropdownMenuItem<int>(
                                              value: version.id,
                                              child: Text(version.code),
                                            ),
                                          )
                                          .toList(growable: false),
                                      onChanged: _onBibleVersionChanged,
                                    ),
                                  ),
                                  if (showBibleVersionName) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '(${selectedBibleVersion.name})',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                  const Spacer(),
                                  IconButton.filledTonal(
                                    key: const ValueKey(
                                      'copy-bible-text-button',
                                    ),
                                    onPressed: _selectedBibleText == null
                                        ? null
                                        : _copySelectedBibleText,
                                    icon: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      child: _copiedFeedbackVisible
                                          ? const Icon(
                                              key: ValueKey('copied-icon'),
                                              Icons.check_circle,
                                              color: Colors.green,
                                            )
                                          : const Icon(
                                              key: ValueKey('copy-icon'),
                                              Icons.content_copy_outlined,
                                            ),
                                    ),
                                    tooltip: 'Copy biblical text',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('biblical-text-field'),
                                  controller: _bibleTextController,
                                  readOnly: true,
                                  expands: true,
                                  maxLines: null,
                                  minLines: null,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: hasRealBibleText
                                      ? theme.textTheme.bodyMedium?.copyWith(
                                          fontStyle: FontStyle.italic,
                                          fontSize: 18,
                                          fontFamily: 'Times New Roman',
                                          fontFamilyFallback: const [
                                            'Times',
                                            'Noto Serif',
                                            'serif',
                                          ],
                                        )
                                      : theme.textTheme.bodyMedium?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  decoration: InputDecoration(
                                    border: const OutlineInputBorder(),
                                    alignLabelWithHint: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (_loadingBibleText) ...[
            const ModalBarrier(dismissible: false, color: Color(0x66000000)),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Widget _buildBodyEditor(ThemeData theme) {
    final hasText = _textController.text.isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: _isEditing && _verseMatches.isEmpty
              ? TextField(
                  key: const ValueKey('source-text-field'),
                  focusNode: _focusNode,
                  controller: _textController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
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
                )
              : (_verseMatches.isNotEmpty && !_isEditing
                    ? _RichTextViewer(
                        text: _textController.text,
                        verseMatches: _verseMatches,
                        activeReference: _activeReference,
                        onReferenceTap: _onReferenceTap,
                      )
                    : TextField(
                        key: const ValueKey('source-text-field'),
                        focusNode: _focusNode,
                        controller: _textController,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
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
                      )),
        ),
        if (kEnableHistoryFeature) ...[
          const SizedBox(height: 16),
          Text('Recent scans', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const _EmptyState(message: 'Your saved history will appear here.')
          else
            ..._history.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HistoryCard(record: record),
              ),
            ),
        ],
      ],
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
    required this.compactVertical,
    required this.cameraSupported,
    required this.onSourceChanged,
    required this.onPickFile,
    required this.onPickImage,
    required this.onOpenCamera,
  });

  final InputSource selected;
  final bool processing;
  final String? lastImagePath;
  final bool compactVertical;
  final bool cameraSupported;
  final ValueChanged<InputSource> onSourceChanged;
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final VoidCallback onOpenCamera;

  Future<void> _showImagePreviewDialog(BuildContext context, String imagePath) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Container(
                color: Colors.black,
                constraints: const BoxConstraints(minHeight: 240),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 5.0,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: Center(
                    child: Image.file(File(imagePath), fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveSelected = !cameraSupported && selected == InputSource.camera
        ? InputSource.image
        : selected;
    final cardPadding = compactVertical ? 12.0 : 16.0;
    final titleSpacing = compactVertical ? 8.0 : 10.0;
    final controlsSpacing = compactVertical ? 8.0 : 12.0;
    return SizedBox(
      width: double.infinity,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Input source', style: theme.textTheme.titleSmall),
              SizedBox(height: titleSpacing),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact =
                      constraints.maxWidth < 420 || compactVertical;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SegmentedButton<InputSource>(
                              showSelectedIcon: false,
                              style: ButtonStyle(
                                padding: WidgetStateProperty.resolveWith((
                                  states,
                                ) {
                                  if (isCompact) {
                                    return const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    );
                                  }
                                  return const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  );
                                }),
                              ),
                              segments: [
                                ButtonSegment(
                                  value: InputSource.text,
                                  icon: const Icon(Icons.text_fields),
                                  label: Text(
                                    isCompact ? 'Text' : 'Text',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ButtonSegment(
                                  value: InputSource.image,
                                  icon: const Icon(Icons.image_outlined),
                                  label: Text(
                                    isCompact ? 'Image' : 'Image',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (cameraSupported)
                                  ButtonSegment(
                                    value: InputSource.camera,
                                    icon: const Icon(Icons.camera_alt_outlined),
                                    label: Text(
                                      isCompact ? 'Cam' : 'Camera',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              selected: {effectiveSelected},
                              onSelectionChanged: (s) =>
                                  onSourceChanged(s.first),
                            ),
                            SizedBox(height: controlsSpacing),
                            SizedBox(
                              width: double.infinity,
                              child: _buildActions(context, effectiveSelected),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _buildPreview(
                          context,
                          isCompact,
                          effectiveSelected,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, InputSource selectedSource) {
    switch (selectedSource) {
      case InputSource.text:
        return FilledButton.icon(
          onPressed: processing ? null : onPickFile,
          icon: processing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.file_open_outlined),
          label: Text(processing ? 'Processing…' : 'Load from file'),
        );

      case InputSource.image:
        return FilledButton.icon(
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

  Widget _buildPreview(
    BuildContext context,
    bool isCompact,
    InputSource selectedSource,
  ) {
    final theme = Theme.of(context);
    final previewHeight = isCompact ? 112.0 : 140.0;
    final previewIconSize = isCompact ? 30.0 : 36.0;
    final previewPadding = isCompact ? 10.0 : 12.0;
    final previewRadius = isCompact ? 10.0 : 12.0;

    switch (selectedSource) {
      case InputSource.text:
        return Container(
          height: previewHeight,
          padding: EdgeInsets.all(previewPadding),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.35,
            ),
            borderRadius: BorderRadius.circular(previewRadius),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.description_outlined,
                size: previewIconSize,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                'Text file',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );

      case InputSource.image:
      case InputSource.camera:
        if (lastImagePath != null && File(lastImagePath!).existsSync()) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(previewRadius),
              onTap: () => _showImagePreviewDialog(context, lastImagePath!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(previewRadius),
                child: Image.file(
                  File(lastImagePath!),
                  height: previewHeight,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        }

        return Container(
          height: previewHeight,
          padding: EdgeInsets.all(previewPadding),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.35,
            ),
            borderRadius: BorderRadius.circular(previewRadius),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_outlined,
                size: previewIconSize,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                selectedSource == InputSource.camera
                    ? 'No photo yet'
                    : 'No image yet',
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
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
                          border: Border.all(color: Colors.white, width: 3),
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

// ---------------------------------------------------------------------------
// Banner image — swap assets/images/banner_demo.png for your own image
// ---------------------------------------------------------------------------

class _BannerImage extends StatelessWidget {
  const _BannerImage();

  static const _asset = 'assets/images/banner_demo.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        _asset,
        width: double.infinity,
        height: 160,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rich text viewer — shows source text with inline tappable reference spans
// ---------------------------------------------------------------------------

class _RichTextViewer extends StatelessWidget {
  const _RichTextViewer({
    required this.text,
    required this.verseMatches,
    required this.activeReference,
    required this.onReferenceTap,
  });

  final String text;
  final List<VerseMatch> verseMatches;
  final String? activeReference;
  final ValueChanged<String> onReferenceTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.6,
    );

    final spans = <InlineSpan>[];
    final sorted = [...verseMatches]
      ..sort((a, b) => a.start.compareTo(b.start));
    var pos = 0;

    for (final vm in sorted) {
      final start = vm.start.clamp(0, text.length);
      final end = vm.end.clamp(0, text.length);
      if (start >= end) continue;

      if (start > pos) {
        spans.add(TextSpan(text: text.substring(pos, start), style: baseStyle));
      }

      final isActive = vm.reference == activeReference;
      final color = isActive ? _kMagenta : _kHighlightBlue;

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            key: ValueKey('ref-chip-${vm.reference}'),
            onTap: () => onReferenceTap(vm.reference),
            child: Text(
              text.substring(start, end),
              style: baseStyle?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: color,
              ),
            ),
          ),
        ),
      );
      pos = end;
    }

    if (pos < text.length) {
      spans.add(TextSpan(text: text.substring(pos), style: baseStyle));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText.rich(
        TextSpan(style: baseStyle, children: spans),
        minLines: 4,
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
              const Text('No se detectaron citas bíblicas.')
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

class BibleVersionOption {
  const BibleVersionOption({
    required this.id,
    required this.code,
    required this.name,
    this.enabled = true,
  });

  final int id;
  final String code;
  final String name;
  final bool enabled;
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
      version: 3,
      onCreate: (db, version) async {
        await db.execute(_kCreateCapturesTableSql);
        await db.execute(_kCreateSettingsTableSql);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(_kCreateSettingsTableSql);
        }
        if (oldVersion < 3) {
          await db.execute(_kCreateSettingsTableSql);
        }
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

  Future<int?> selectedBibleVersionId() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_kBibleVersionSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value'] as String?;
    if (value == null) return null;
    return int.tryParse(value);
  }

  Future<void> setSelectedBibleVersionId(int versionId) async {
    final db = await _db;
    await db.insert('app_settings', <String, Object?>{
      'key': _kBibleVersionSettingKey,
      'value': versionId.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> includeBibleTextInOutput() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_kIncludeBibleTextSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final value = rows.first['value'] as String?;
    return value == 'true';
  }

  Future<void> setIncludeBibleTextInOutput(bool value) async {
    final db = await _db;
    await db.insert('app_settings', <String, Object?>{
      'key': _kIncludeBibleTextSettingKey,
      'value': value ? 'true' : 'false',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> exportDirectoryPath() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_kExportDirectorySettingKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setExportDirectoryPath(String path) async {
    final db = await _db;
    await db.insert('app_settings', <String, Object?>{
      'key': _kExportDirectorySettingKey,
      'value': path,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

const String _kCreateCapturesTableSql = '''
  CREATE TABLE captures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    image_path TEXT NOT NULL,
    recognized_text TEXT NOT NULL,
    references_json TEXT NOT NULL
  )
''';

const String _kCreateSettingsTableSql = '''
  CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
''';

const String _kBibleVersionSettingKey = 'selected_bible_version_id';
const String _kIncludeBibleTextSettingKey = 'include_bible_text_in_output';
const String _kExportDirectorySettingKey = 'export_directory_path';

List<String> extractVerseReferences(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return const [];
  }

  final references = <String>{};

  for (final match in _kFullReferencePattern.allMatches(normalized)) {
    final book = match.group(1)!;
    final chapter = match.group(2)!;
    final verse = match.group(3)!;
    final verseEnd = match.group(4);

    if (!_isKnownBiblicalBook(book)) {
      continue;
    }

    references.add(
      '$book $chapter:$verse${verseEnd == null ? '' : '-$verseEnd'}',
    );

    var cursor = match.end;
    while (cursor < normalized.length) {
      final continuation = _kContinuationPattern.matchAsPrefix(
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

  for (final match in _kChapterOnlyPattern.allMatches(normalized)) {
    final book = match.group(1)!;
    final chapter = match.group(2)!;
    if (!_isKnownBiblicalBook(book)) {
      continue;
    }
    references.add(
      _normalizeChapterOnlyReference(book: book, chapterOrVerse: chapter),
    );
  }

  return references.toList(growable: false);
}

// ---------------------------------------------------------------------------
// Biblical text lookup
// ---------------------------------------------------------------------------

Future<String?> lookupBibleTextFromYouVersion(
  String reference,
  int bibleVersionId,
) async {
  if (kYouVersionAppKey.isEmpty) {
    throw const YouVersionConfigurationException(
      'Missing YOUVERSION_APP_KEY. Run with '
      '--dart-define=YOUVERSION_APP_KEY=<your_app_key>.',
    );
  }

  final match = RegExp(
    r'^(.*)\s+(\d{1,3})(?:(?:\s*:\s*|\s*\.\s*|\s*,\s*|\s+)(\d{1,3})(?:\s*-\s*(\d{1,3}))?)?$',
  ).firstMatch(reference.trim());
  if (match == null) return null;

  final book = _canonicalBookKey(match.group(1)!);
  final usfmBook =
      _kUsfmBookCodeByBookKey[book] ??
      _kUsfmBookCodeByBookKey[_normalizeBookKey(match.group(1)!)];
  if (usfmBook == null) {
    throw YouVersionApiException(
      'Unsupported biblical book for remote lookup: ${match.group(1)}',
    );
  }
  var chapter = match.group(2)!;
  var verse = match.group(3);
  final verseEnd = match.group(4);
  if (verse == null &&
      _kSingleChapterBookKeys.contains(book) &&
      int.parse(chapter) > 1) {
    verse = chapter;
    chapter = '1';
  }
  if (verse == null) {
    return _fetchChapterContentByVerses(
      bibleVersionId: bibleVersionId,
      usfmBook: usfmBook,
      chapter: chapter,
    );
  }

  final passageId = verseEnd == null
      ? '$usfmBook.$chapter.$verse'
      : '$usfmBook.$chapter.$verse-$verseEnd';
  if (verseEnd == null) {
    final content = await _fetchYouVersionPassageContent(
      bibleVersionId: bibleVersionId,
      passageId: passageId,
    );
    return formatBibleTextForDisplay(content: content);
  }

  final startVerseNumber = int.parse(verse);
  final endVerseNumber = int.parse(verseEnd);
  if (endVerseNumber < startVerseNumber) {
    throw YouVersionApiException('Invalid verse range: $reference');
  }

  final formattedLines = <String>[];
  for (
    var verseNumber = startVerseNumber;
    verseNumber <= endVerseNumber;
    verseNumber++
  ) {
    final singleVersePassageId = '$usfmBook.$chapter.$verseNumber';
    final content = await _fetchYouVersionPassageContent(
      bibleVersionId: bibleVersionId,
      passageId: singleVersePassageId,
    );
    final normalizedText = formatBibleTextForDisplay(content: content);
    final formatted = normalizedText == null
        ? null
        : '$verseNumber: $normalizedText';
    if (formatted != null && formatted.isNotEmpty) {
      formattedLines.add(formatted);
    }
  }

  if (formattedLines.isEmpty) return null;
  return formattedLines.join('\n');
}

Future<String> _fetchYouVersionPassageContent({
  required int bibleVersionId,
  required String passageId,
}) async {
  final baseUri = Uri.parse(kYouVersionApiBaseUrl);
  final requestUri = baseUri.replace(
    path: _joinApiPath(
      baseUri.path,
      '/v1/bibles/$bibleVersionId/passages/$passageId',
    ),
  );

  final client = HttpClient();
  try {
    final request = await client.getUrl(requestUri);
    request.headers.set('x-yvp-app-key', kYouVersionAppKey);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YouVersionApiException(
        'YouVersion API returned HTTP ${response.statusCode}: $responseBody',
        statusCode: response.statusCode,
        responseBody: responseBody,
        passageId: passageId,
      );
    }

    final decoded = jsonDecode(responseBody);
    final extractedText = _extractBibleTextFromPayload(decoded);
    if (extractedText == null || extractedText.isEmpty) {
      throw const FormatException(
        'No biblical text found in YouVersion response payload.',
      );
    }
    return extractedText;
  } finally {
    client.close(force: true);
  }
}

Future<String?> _fetchChapterContentByVerses({
  required int bibleVersionId,
  required String usfmBook,
  required String chapter,
}) async {
  const maxVerseProbe = 200;
  final formattedLines = <String>[];
  for (var verseNumber = 1; verseNumber <= maxVerseProbe; verseNumber++) {
    final passageId = '$usfmBook.$chapter.$verseNumber';
    try {
      final content = await _fetchYouVersionPassageContent(
        bibleVersionId: bibleVersionId,
        passageId: passageId,
      );
      final normalizedText = formatBibleTextForDisplay(content: content);
      if (normalizedText != null && normalizedText.isNotEmpty) {
        formattedLines.add('$verseNumber: $normalizedText');
      }
    } on YouVersionApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      if (verseNumber == 1) {
        throw YouVersionApiException(
          'Bible passage $usfmBook.$chapter for version $bibleVersionId not found',
          statusCode: 404,
          passageId: '$usfmBook.$chapter',
        );
      }
      break;
    }
  }
  if (formattedLines.isEmpty) return null;
  return formattedLines.join('\n');
}

String? formatBibleTextForDisplay({required String content}) {
  final normalizedContent = _stripHtml(content).trim();
  if (normalizedContent.isEmpty) return null;
  return normalizedContent;
}

String _normalizeBookKey(String book) {
  return book.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

bool _isKnownBiblicalBook(String book) {
  final normalized = _normalizeBookKey(book);
  return _kKnownBibleBooks.contains(normalized);
}

String _canonicalBookKey(String book) {
  final normalized = _normalizeBookKey(book);
  switch (normalized) {
    case '1cor':
    case '1corinthians':
      return '1cor';
    case '2cor':
    case '2corinthians':
      return '2cor';
    case 'john':
    case 'jhn':
      return 'john';
    case 'romans':
    case 'rom':
      return 'romans';
    case 'philippians':
    case 'phil':
      return 'philippians';
    case 'psalm':
    case 'psalms':
    case 'salmos':
    case 'sal':
    case 'ps':
      return 'psalm';
    case 'proverbs':
    case 'prov':
      return 'proverbs';
    case 'jeremiah':
    case 'jer':
      return 'jeremiah';
    case 'isaiah':
    case 'isa':
      return 'isaiah';
    case 'joshua':
    case 'josh':
      return 'joshua';
    case 'matthew':
    case 'matt':
      return 'matthew';
    case 'ephesians':
    case 'eph':
    case 'efe':
    case 'efesios':
      return 'ephesians';
    case 'judas':
    default:
      return normalized;
  }
}

String _normalizeChapterOnlyReference({
  required String book,
  required String chapterOrVerse,
}) {
  final canonicalBook = _canonicalBookKey(book);
  if (_kSingleChapterBookKeys.contains(canonicalBook)) {
    return '$book 1:$chapterOrVerse';
  }
  return '$book $chapterOrVerse';
}

const Set<String> _kKnownBibleBooks = {
  'genesis',
  'gen',
  'exodus',
  'exo',
  'leviticus',
  'lev',
  'numbers',
  'num',
  'deuteronomy',
  'deut',
  'joshua',
  'josh',
  'judges',
  'judg',
  'ruth',
  'rut',
  '1samuel',
  '1sam',
  '2samuel',
  '2sam',
  '1kings',
  '1kng',
  '2kings',
  '2kng',
  '1chronicles',
  '1chr',
  '2chronicles',
  '2chr',
  'ezra',
  'ezr',
  'nehemiah',
  'neh',
  'esther',
  'est',
  'job',
  'psalm',
  'psalms',
  'salmos',
  'sal',
  'ps',
  'proverbs',
  'prov',
  'ecclesiastes',
  'eccl',
  'songofsolomon',
  'song',
  'isaiah',
  'isa',
  'jeremiah',
  'jer',
  'lamentations',
  'lam',
  'ezekiel',
  'ezek',
  'daniel',
  'dan',
  'hosea',
  'hos',
  'hch',
  'joel',
  'jol',
  'amos',
  'am',
  'obadiah',
  'obad',
  'jonah',
  'jon',
  'micah',
  'mic',
  'nahum',
  'nah',
  'habakkuk',
  'hab',
  'zephaniah',
  'zep',
  'haggai',
  'hag',
  'zechariah',
  'zech',
  'malachi',
  'mal',
  'matthew',
  'matt',
  'mark',
  'mrk',
  'mt',
  'luke',
  'luk',
  'lc',
  'john',
  'jhn',
  'acts',
  'romans',
  'rom',
  '1cor',
  '1corinthians',
  '2cor',
  '2corinthians',
  'cor',
  'galatians',
  'gal',
  'ephesians',
  'eph',
  'efe',
  'efesios',
  'philippians',
  'phil',
  'colossians',
  'col',
  '1thessalonians',
  '1thes',
  '2thessalonians',
  '2thes',
  'tes',
  '1tes',
  '2tes',
  '1timothy',
  '1tim',
  '2timothy',
  '2tim',
  'titus',
  'tit',
  'tim',
  'philemon',
  'phm',
  'hebrews',
  'heb',
  'james',
  'jam',
  '1peter',
  '1pet',
  '2peter',
  '2pet',
  '1john',
  '1jn',
  '2john',
  '2jn',
  '3john',
  '3jn',
  'jude',
  'jud',
  'judas',
  'revelation',
  'rev',
};

const _kUsfmBookCodeByBookKey = <String, String>{
  'genesis': 'GEN',
  'gen': 'GEN',
  'exodus': 'EXO',
  'exo': 'EXO',
  'leviticus': 'LEV',
  'lev': 'LEV',
  'numbers': 'NUM',
  'num': 'NUM',
  'deuteronomy': 'DEU',
  'deut': 'DEU',
  'joshua': 'JOS',
  'josh': 'JOS',
  'judges': 'JDG',
  'judg': 'JDG',
  'ruth': 'RUT',
  'rut': 'RUT',
  '1samuel': '1SA',
  '1sam': '1SA',
  '2samuel': '2SA',
  '2sam': '2SA',
  '1kings': '1KI',
  '1kng': '1KI',
  '2kings': '2KI',
  '2kng': '2KI',
  '1chronicles': '1CH',
  '1chr': '1CH',
  '2chronicles': '2CH',
  '2chr': '2CH',
  'ezra': 'EZR',
  'ezr': 'EZR',
  'nehemiah': 'NEH',
  'neh': 'NEH',
  'esther': 'EST',
  'est': 'EST',
  'job': 'JOB',
  'psalm': 'PSA',
  'psalms': 'PSA',
  'salmos': 'PSA',
  'sal': 'PSA',
  'ps': 'PSA',
  'proverbs': 'PRO',
  'prov': 'PRO',
  'ecclesiastes': 'ECC',
  'eccl': 'ECC',
  'songofsolomon': 'SNG',
  'song': 'SNG',
  'isaiah': 'ISA',
  'isa': 'ISA',
  'jeremiah': 'JER',
  'jer': 'JER',
  'lamentations': 'LAM',
  'lam': 'LAM',
  'ezekiel': 'EZK',
  'ezek': 'EZK',
  'daniel': 'DAN',
  'dan': 'DAN',
  'hosea': 'HOS',
  'hos': 'HOS',
  'joel': 'JOL',
  'jol': 'JOL',
  'amos': 'AMO',
  'am': 'AMO',
  'obadiah': 'OBA',
  'obad': 'OBA',
  'jonah': 'JON',
  'jon': 'JON',
  'micah': 'MIC',
  'mic': 'MIC',
  'nahum': 'NAM',
  'nah': 'NAM',
  'habakkuk': 'HAB',
  'hab': 'HAB',
  'zephaniah': 'ZEP',
  'zep': 'ZEP',
  'haggai': 'HAG',
  'hag': 'HAG',
  'zechariah': 'ZEC',
  'zech': 'ZEC',
  'malachi': 'MAL',
  'mal': 'MAL',
  'matthew': 'MAT',
  'matt': 'MAT',
  'mark': 'MRK',
  'mrk': 'MRK',
  'mt': 'MAT',
  'luke': 'LUK',
  'luk': 'LUK',
  'lc': 'LUK',
  'john': 'JHN',
  'jhn': 'JHN',
  'acts': 'ACT',
  'hch': 'ACT',
  'romans': 'ROM',
  'rom': 'ROM',
  '1cor': '1CO',
  '1corinthians': '1CO',
  '2cor': '2CO',
  '2corinthians': '2CO',
  'galatians': 'GAL',
  'gal': 'GAL',
  'ephesians': 'EPH',
  'eph': 'EPH',
  'efe': 'EPH',
  'efesios': 'EPH',
  'philippians': 'PHP',
  'phil': 'PHP',
  'colossians': 'COL',
  'col': 'COL',
  '1thessalonians': '1TH',
  '1thes': '1TH',
  '1tes': '1TH',
  '2thessalonians': '2TH',
  '2thes': '2TH',
  '2tes': '2TH',
  '1timothy': '1TI',
  '1tim': '1TI',
  '2timothy': '2TI',
  '2tim': '2TI',
  'titus': 'TIT',
  'tit': 'TIT',
  'philemon': 'PHM',
  'phm': 'PHM',
  'hebrews': 'HEB',
  'heb': 'HEB',
  'james': 'JAS',
  'jam': 'JAS',
  '1peter': '1PE',
  '1pet': '1PE',
  '2peter': '2PE',
  '2pet': '2PE',
  '1john': '1JN',
  '1jn': '1JN',
  '2john': '2JN',
  '2jn': '2JN',
  '3john': '3JN',
  '3jn': '3JN',
  'jude': 'JUD',
  'jud': 'JUD',
  'judas': 'JUD',
  'revelation': 'REV',
  'rev': 'REV',
};

const Set<String> _kSingleChapterBookKeys = {
  'obadiah',
  'obad',
  'philemon',
  'phm',
  '2john',
  '2jn',
  '3john',
  '3jn',
  'jude',
  'jud',
  'judas',
};

String _joinApiPath(String basePath, String suffix) {
  final normalizedBase = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  final normalizedSuffix = suffix.startsWith('/') ? suffix : '/$suffix';
  if (normalizedBase.isEmpty) return normalizedSuffix;
  return '$normalizedBase$normalizedSuffix';
}

String? _extractBibleTextFromPayload(Object? payload) {
  final directText = _extractTextCandidate(payload);
  if (directText != null) return directText;

  if (payload is Map<String, dynamic>) {
    for (final key in ['data', 'passage', 'content', 'items', 'results']) {
      final nested = _extractBibleTextFromPayload(payload[key]);
      if (nested != null) return nested;
    }
  }

  if (payload is List) {
    for (final value in payload) {
      final nested = _extractBibleTextFromPayload(value);
      if (nested != null) return nested;
    }
  }

  return null;
}

String? _extractTextCandidate(Object? payload) {
  if (payload is String) {
    final normalized = _stripHtml(payload).trim();
    return normalized.isEmpty ? null : normalized;
  }

  if (payload is! Map<String, dynamic>) return null;

  for (final key in ['plain_text', 'text', 'body', 'content']) {
    final value = payload[key];
    if (value is String) {
      final normalized = _stripHtml(value).trim();
      if (normalized.isNotEmpty) return normalized;
    }
  }
  return null;
}

String _stripHtml(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class YouVersionConfigurationException implements Exception {
  const YouVersionConfigurationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class YouVersionApiException implements Exception {
  const YouVersionApiException(
    this.message, {
    this.statusCode,
    this.responseBody,
    this.passageId,
  });
  final String message;
  final int? statusCode;
  final String? responseBody;
  final String? passageId;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

const _kHighlightBlue = Color(0xFF1565C0);
const _kMagenta = Color(0xFFAD1457);

// ---------------------------------------------------------------------------
// Highlight text controller
// ---------------------------------------------------------------------------

class HighlightTextEditingController extends TextEditingController {
  List<({int start, int end, Color color})> _highlights = const [];

  set highlights(List<({int start, int end, Color color})> value) {
    _highlights = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_highlights.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final spans = <InlineSpan>[];
    final sorted = [..._highlights]..sort((a, b) => a.start.compareTo(b.start));
    var pos = 0;

    for (final h in sorted) {
      final start = h.start.clamp(0, text.length);
      final end = h.end.clamp(0, text.length);
      if (start >= end) continue;
      if (start > pos) {
        spans.add(TextSpan(text: text.substring(pos, start), style: style));
      }
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: (style ?? const TextStyle()).copyWith(color: h.color),
        ),
      );
      pos = end;
    }

    if (pos < text.length) {
      spans.add(TextSpan(text: text.substring(pos), style: style));
    }

    return TextSpan(style: style, children: spans);
  }
}

// ---------------------------------------------------------------------------
// Verse match (reference + position in source text)
// ---------------------------------------------------------------------------

class VerseMatch {
  const VerseMatch({
    required this.reference,
    required this.start,
    required this.end,
  });

  final String reference;
  final int start;
  final int end;
}

// ---------------------------------------------------------------------------
// Regex patterns (shared by both extraction functions)
// ---------------------------------------------------------------------------

final _kFullReferencePattern = RegExp(
  r'\b((?:[1-3]\s+)?[A-Za-zÁÉÍÓÚáéíóúÑñ]+\.?)\s+(\d{1,3})\s*(?::|\.|,|\s)\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?\b',
);

final _kContinuationPattern = RegExp(
  r'^\s*[,;]\s*(\d{1,3})\s*(?::|\.|,|\s)\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?',
);

final _kChapterOnlyPattern = RegExp(
  r'\b((?:[1-3]\s+)?[A-Za-zÁÉÍÓÚáéíóúÑñ]+\.?)\s+(\d{1,3})\b(?!\s*(?::|\.|,)\s*\d)(?!\s+\d)',
);

// ---------------------------------------------------------------------------
// extractVerseMatches — returns references WITH their positions in [text]
// ---------------------------------------------------------------------------

List<VerseMatch> extractVerseMatches(String text) {
  if (text.trim().isEmpty) return const [];

  final matches = <VerseMatch>[];

  for (final match in _kFullReferencePattern.allMatches(text)) {
    final book = match.group(1)!;
    final chapter = match.group(2)!;
    final verse = match.group(3)!;
    final verseEnd = match.group(4);

    if (!_isKnownBiblicalBook(book)) {
      continue;
    }

    matches.add(
      VerseMatch(
        reference:
            '$book $chapter:$verse${verseEnd == null ? '' : '-$verseEnd'}',
        start: match.start,
        end: match.end,
      ),
    );

    var cursor = match.end;
    while (cursor < text.length) {
      final cont = _kContinuationPattern.matchAsPrefix(text.substring(cursor));
      if (cont == null) break;
      final contChapter = cont.group(1)!;
      final contVerse = cont.group(2)!;
      final contVerseEnd = cont.group(3);
      matches.add(
        VerseMatch(
          reference:
              '$book $contChapter:$contVerse${contVerseEnd == null ? '' : '-$contVerseEnd'}',
          start: cursor,
          end: cursor + cont.end,
        ),
      );
      cursor += cont.end;
    }
  }

  for (final match in _kChapterOnlyPattern.allMatches(text)) {
    final book = match.group(1)!;
    final chapter = match.group(2)!;
    if (!_isKnownBiblicalBook(book)) {
      continue;
    }
    matches.add(
      VerseMatch(
        reference: _normalizeChapterOnlyReference(
          book: book,
          chapterOrVerse: chapter,
        ),
        start: match.start,
        end: match.end,
      ),
    );
  }

  return matches;
}

String _formatTimestamp(DateTime dateTime) {
  final local = dateTime.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

// ============================================================
// WIZARD UI — VerseCatch_UI_Wizard_Specification.md
// ============================================================

enum _WizardStep {
  chooseSource,
  acquireContent,
  reviewText,
  detectRefs,
  exploreRefs,
  finish,
}

enum _WizardSource { text, file, image, camera, history }

enum _FinishAction {
  none,
  savedToHistory,
  copiedCitations,
  copiedScannedResult,
  exported,
}

extension _WizardStepLabel on _WizardStep {
  String get label => switch (this) {
        _WizardStep.chooseSource => 'Elegir origen',
        _WizardStep.acquireContent => 'Obtener texto',
        _WizardStep.reviewText => 'Revisar texto',
        _WizardStep.detectRefs => 'Detectar citas',
        _WizardStep.exploreRefs => 'Explorar citas',
        _WizardStep.finish => 'Guardar',
      };
}

// ============================================================
// WizardHomePage
// ============================================================

class WizardHomePage extends StatefulWidget {
  const WizardHomePage({super.key, required this.bibleTextLookup});
  final BibleTextLookup bibleTextLookup;

  @override
  State<WizardHomePage> createState() => _WizardHomePageState();
}

class _WizardHomePageState extends State<WizardHomePage> {
  final _store = VerseCaptureStore.instance;
  static const _ocrChannel = MethodChannel('versecatch/ocr');

  _WizardStep _step = _WizardStep.chooseSource;
  _WizardSource? _source;

  final _textController = TextEditingController();
  String? _imagePath;
  bool _processing = false;

  List<({String reference, int count})> _groupedRefs = const [];
  String? _activeReference;
  int _currentRefIndex = 0;

  String? _bibleText;
  String _bibleMessage = kNoBibleTextMessage;
  bool _loadingBibleText = false;
  int _bibleLookupRequestId = 0;
  int _selectedBibleVersionId = kYouVersionBibleVersionId;
  bool _copiedFeedbackVisible = false;
  Timer? _copyFeedbackTimer;
  bool _includeBibleTextInOutput = false;
  String? _exportDirectoryPath;
  bool _cancelCurrentAction = false;

  List<CaptureRecord> _history = const [];
  bool _savedToHistory = false;
  _FinishAction _completedAction = _FinishAction.none;
  Duration? _detectionDuration;

  bool get _supportsCameraCapture =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadBibleVersionPreference();
    _loadOutputPreferences();
  }

  @override
  void dispose() {
    _copyFeedbackTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final records = await _store.recentCaptures();
    if (!mounted) return;
    setState(() => _history = records);
  }

  Future<void> _loadBibleVersionPreference() async {
    final id = await _store.selectedBibleVersionId();
    if (!mounted || id == null) return;
    final ok = kSupportedBibleVersions.any((v) => v.id == id && v.enabled);
    if (!ok) return;
    setState(() => _selectedBibleVersionId = id);
  }

  Future<void> _loadOutputPreferences() async {
    final includeBibleText = await _store.includeBibleTextInOutput();
    final exportDirectory = await _store.exportDirectoryPath();
    if (!mounted) return;
    setState(() {
      _includeBibleTextInOutput = includeBibleText;
      _exportDirectoryPath = exportDirectory;
    });
  }

  BibleVersionOption _selectedBibleVersionOption() {
    return kSupportedBibleVersions.firstWhere(
      (version) => version.id == _selectedBibleVersionId,
      orElse: () => kSupportedBibleVersions.first,
    );
  }

  void _resetWizard() {
    _textController.clear();
    setState(() {
      _step = _WizardStep.chooseSource;
      _source = null;
      _imagePath = null;
      _processing = false;
      _groupedRefs = const [];
      _activeReference = null;
      _currentRefIndex = 0;
      _bibleText = null;
      _bibleMessage = kNoBibleTextMessage;
      _loadingBibleText = false;
      _bibleLookupRequestId = 0;
      _copiedFeedbackVisible = false;
      _savedToHistory = false;
      _completedAction = _FinishAction.none;
      _cancelCurrentAction = false;
      _detectionDuration = null;
    });
    _loadHistory();
  }

  void _selectSource(_WizardSource source) {
    setState(() {
      _source = source;
      _step = _WizardStep.acquireContent;
    });
    if (source == _WizardSource.camera) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
    }
  }

  void _advanceToReview() => setState(() => _step = _WizardStep.reviewText);

  Future<void> _runDetection() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final start = DateTime.now();
    setState(() => _step = _WizardStep.detectRefs);
    final matches = extractVerseMatches(text);
    final counts = <String, int>{};
    for (final m in matches) {
      counts[m.reference] = (counts[m.reference] ?? 0) + 1;
    }
    final grouped = counts.entries
        .map((e) => (reference: e.key, count: e.value))
        .toList(growable: false);
    final duration = DateTime.now().difference(start);
    if (!mounted) return;
    setState(() {
      _groupedRefs = grouped;
      _detectionDuration = duration;
      if (grouped.isNotEmpty) {
        _activeReference = grouped.first.reference;
        _currentRefIndex = 0;
      }
    });
  }

  void _goToExplore() {
    setState(() => _step = _WizardStep.exploreRefs);
    _loadBibleText();
  }

  void _selectRef(String reference, int index) {
    if (_activeReference == reference) return;
    setState(() {
      _activeReference = reference;
      _currentRefIndex = index;
      _bibleText = null;
      _bibleMessage = kLoadingBibleTextMessage;
    });
    _loadBibleText();
  }

  void _navigateRef(int delta) {
    if (_groupedRefs.isEmpty) return;
    final newIndex =
        (_currentRefIndex + delta).clamp(0, _groupedRefs.length - 1);
    if (newIndex == _currentRefIndex) return;
    _selectRef(_groupedRefs[newIndex].reference, newIndex);
  }

  Future<void> _loadBibleText() async {
    final ref = _activeReference;
    if (ref == null) return;
    final reqId = ++_bibleLookupRequestId;
    setState(() {
      _loadingBibleText = true;
      _bibleMessage = kLoadingBibleTextMessage;
      _bibleText = null;
    });
    try {
      final text = await widget.bibleTextLookup(ref, _selectedBibleVersionId);
      if (!mounted || reqId != _bibleLookupRequestId) return;
      final trimmed = text?.trim();
      setState(() {
        _bibleText =
            (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
        _bibleMessage = _bibleText != null
            ? kNoBibleTextMessage
            : 'No se encontró texto para $ref.';
      });
    } on YouVersionConfigurationException catch (e) {
      if (!mounted || reqId != _bibleLookupRequestId) return;
      setState(() => _bibleMessage = e.message);
    } on YouVersionApiException catch (e) {
      if (!mounted || reqId != _bibleLookupRequestId) return;
      setState(() => _bibleMessage = e.message);
    } on SocketException catch (e) {
      if (!mounted || reqId != _bibleLookupRequestId) return;
      setState(() => _bibleMessage = 'Error de red: $e');
    } on FormatException catch (e) {
      if (!mounted || reqId != _bibleLookupRequestId) return;
      setState(() => _bibleMessage = 'Respuesta inválida: $e');
    } finally {
      if (mounted && reqId == _bibleLookupRequestId) {
        setState(() => _loadingBibleText = false);
      }
    }
  }

  Future<void> _onBibleVersionChanged(int? id) async {
    if (id == null || id == _selectedBibleVersionId) return;
    setState(() => _selectedBibleVersionId = id);
    await _store.setSelectedBibleVersionId(id);
    await _loadBibleText();
  }

  Future<void> _toggleIncludeBibleText(bool value) async {
    setState(() => _includeBibleTextInOutput = value);
    await _store.setIncludeBibleTextInOutput(value);
  }

  Future<({String content, String? warning})> _buildOutputContentForCurrentSelection({
    required String sourceText,
  }) async {
    final version = _selectedBibleVersionOption();
    final payload = await _buildClipboardPayloadForCurrentSelection(
      sourceText: sourceText,
    );
    return (
      content: buildOutputContent(
        sourceText: sourceText,
        groupedRefs: _groupedRefs,
        includeBibleText: _includeBibleTextInOutput,
        biblicalTexts: payload.biblicalTexts,
        versionLabel: version.code,
      ),
      warning: payload.warning,
    );
  }

  Future<({Map<String, String> biblicalTexts, String? warning})>
      _buildClipboardPayloadForCurrentSelection({
    required String sourceText,
    void Function(int current, int total)? onProgress,
  }) async {
    final biblicalTexts = <String, String>{};
    String? warning;
    if (_includeBibleTextInOutput && _groupedRefs.isNotEmpty) {
      final collected = await _collectBibleTextsForReferences(
        _groupedRefs.map((ref) => ref.reference).toList(growable: false),
        onProgress: onProgress,
      );
      biblicalTexts.addAll(collected.biblicalTexts);
      if (collected.errors.isNotEmpty) {
        warning = collected.errors.join('\n');
      }
    }
    return (biblicalTexts: biblicalTexts, warning: warning);
  }

  Future<({Map<String, String> biblicalTexts, List<String> errors})>
      _collectBibleTextsForReferences(
    List<String> references, {
    void Function(int current, int total)? onProgress,
  }) async {
    final collected = <String, String>{};
    final errors = <String>[];
    final random = Random();
    final rateLimitWindowMs =
        kAppEnvironment.toLowerCase() == 'live' ? 1600 : 900;
    var nextAllowedAt = DateTime.now();

    for (var index = 0; index < references.length; index++) {
      if (_cancelCurrentAction) break;
      onProgress?.call(index + 1, references.length);
      final reference = references[index];
      if (index > 0) {
        final now = DateTime.now();
        final waitMs = nextAllowedAt.difference(now).inMilliseconds;
        final randomJitterMs = random.nextInt(180) + 70;
        final delayMs = waitMs > 0 ? waitMs + randomJitterMs : randomJitterMs;
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      try {
        final text = await widget.bibleTextLookup(
          reference,
          _selectedBibleVersionId,
        );
        final trimmed = text?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          collected[reference] = trimmed;
        }
      } catch (error, stackTrace) {
        final detail = error.toString();
        errors.add('$reference: $detail');
        debugPrint('Bible text lookup failed for $reference: $error\n$stackTrace');
      } finally {
        nextAllowedAt = DateTime.now().add(
          Duration(milliseconds: rateLimitWindowMs),
        );
      }
    }
    return (biblicalTexts: collected, errors: errors);
  }

  Future<void> _copyBibleText() async {
    final ref = _activeReference;
    final text = _bibleText;
    if (ref == null || text == null) return;
    final version = kSupportedBibleVersions.firstWhere(
      (v) => v.id == _selectedBibleVersionId,
      orElse: () => kSupportedBibleVersions.first,
    );
    await Clipboard.setData(
      ClipboardData(text: '$ref (${version.code})\n"$text"'),
    );
    if (!mounted) return;
    setState(() => _copiedFeedbackVisible = true);
    _copyFeedbackTimer?.cancel();
    _copyFeedbackTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _copiedFeedbackVisible = false);
    });
  }

  Future<T?> _showActionProgressDialog<T>({
    required String loadingMessage,
    required Future<T> Function(void Function(int current, int total) updateProgress)
        action,
  }) async {
    final startedAt = DateTime.now();
    final progressState = ValueNotifier<({int current, int total, bool completed})>(
      (current: 0, total: 0, completed: false),
    );
    void Function()? refreshDialog;
    showDialog<T?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            refreshDialog = () => setState(() {});
            final theme = Theme.of(dialogContext);
            final currentProgress = progressState.value;
            return AlertDialog(
              content: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: currentProgress.completed
                        ? Icon(
                            Icons.check_circle,
                            size: 24,
                            color: Colors.green.shade600,
                          )
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentProgress.completed ? 'Listo' : loadingMessage,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          buildProcessingStatusLabel(
                            current: currentProgress.current,
                            total: currentProgress.total,
                            completed: currentProgress.completed,
                            elapsed: DateTime.now().difference(startedAt),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancelar',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _cancelCurrentAction = true;
                      if (Navigator.of(dialogContext).canPop()) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    try {
      final result = await action((current, total) {
        if (_cancelCurrentAction) return;
        progressState.value = (current: current, total: total, completed: false);
        refreshDialog?.call();
      });
      if (_cancelCurrentAction) {
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        return null;
      }
      progressState.value = (
        current: progressState.value.total,
        total: progressState.value.total,
        completed: true,
      );
      refreshDialog?.call();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      return result;
    } catch (error) {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      if (!mounted) return null;
      await _showOutputFailureDialog(error);
      return null;
    } finally {
      _cancelCurrentAction = false;
    }
  }

  Future<void> _copyAllReferences() async {
    final text = _textController.text.trim();
    if (_groupedRefs.isEmpty || text.isEmpty) return;

    try {
      final version = _selectedBibleVersionOption();
      final payload = await _showActionProgressDialog<({Map<String, String> biblicalTexts, String? warning})>(
        loadingMessage: 'Preparando copia de citas…',
        action: (updateProgress) async {
          return _buildClipboardPayloadForCurrentSelection(
            sourceText: text,
            onProgress: updateProgress,
          );
        },
      );
      if (payload == null || _cancelCurrentAction) return;
      if (payload.warning != null) {
        await _showOutputFailureDialog(payload.warning!);
      }
      final clipboardContent = buildCitationsClipboardContent(
        groupedRefs: _groupedRefs,
        includeBibleText: _includeBibleTextInOutput,
        biblicalTexts: payload.biblicalTexts,
        versionLabel: version.code,
      );
      await Clipboard.setData(ClipboardData(text: clipboardContent));
      if (!mounted) return;
      setState(() => _completedAction = _FinishAction.copiedCitations);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Citas copiadas')),
      );
    } catch (error) {
      if (!mounted) return;
      await _showOutputFailureDialog(error);
    }
  }

  Future<void> _shareResult() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    try {
      final version = _selectedBibleVersionOption();
      final payload = await _showActionProgressDialog<({Map<String, String> biblicalTexts, String? warning})>(
        loadingMessage: 'Preparando resultado escaneado…',
        action: (updateProgress) async {
          return _buildClipboardPayloadForCurrentSelection(
            sourceText: text,
            onProgress: updateProgress,
          );
        },
      );
      if (payload == null || _cancelCurrentAction) return;
      if (payload.warning != null) {
        await _showOutputFailureDialog(payload.warning!);
      }
      final clipboardContent = buildScannedResultClipboardContent(
        sourceText: text,
        groupedRefs: _groupedRefs,
        includeBibleText: _includeBibleTextInOutput,
        biblicalTexts: payload.biblicalTexts,
        versionLabel: version.code,
      );
      await Clipboard.setData(ClipboardData(text: clipboardContent));
      if (!mounted) return;
      setState(() => _completedAction = _FinishAction.copiedScannedResult);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resultado copiado al portapapeles'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await _showOutputFailureDialog(error);
    }
  }

  Future<void> _exportText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final defaultDirectory = await _resolveExportDirectoryPath();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final defaultFileName = 'versecatch_$timestamp.txt';
    final fileNameController = TextEditingController(text: defaultFileName);
    final directoryController = TextEditingController(text: defaultDirectory.path);
    final result = await showDialog<({String directoryPath, String fileName})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Exportar texto'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Elige la carpeta de destino y el nombre del archivo.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fileNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del archivo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: directoryController,
                            decoration: const InputDecoration(
                              labelText: 'Carpeta destino',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: () => setState(() {
                            directoryController.text = defaultDirectory.path;
                          }),
                          child: const Text('Usar ruta'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    (
                      directoryPath: directoryController.text.trim(),
                      fileName: fileNameController.text.trim().isEmpty
                          ? defaultFileName
                          : fileNameController.text.trim(),
                    ),
                  ),
                  child: const Text('Exportar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;

    final selectedDirectory = Directory(result.directoryPath);
    if (!await selectedDirectory.exists()) {
      await selectedDirectory.create(recursive: true);
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _includeBibleTextInOutput
                        ? 'Obteniendo textos bíblicos…'
                        : 'Preparando exportación…',
                    key: ValueKey(_includeBibleTextInOutput),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      final buildResult = await _buildOutputContentForCurrentSelection(
        sourceText: text,
      );
      if (buildResult.warning != null) {
        await _showOutputFailureDialog(buildResult.warning!);
      }
      final fileName = result.fileName.trim().isEmpty
          ? defaultFileName
          : result.fileName.trim();
      final sanitizedFileName = fileName.endsWith('.txt')
          ? fileName
          : '$fileName.txt';
      final filePath = p.join(selectedDirectory.path, sanitizedFileName);
      await File(filePath).writeAsString(buildResult.content);
      await _store.setExportDirectoryPath(selectedDirectory.path);
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      setState(() => _completedAction = _FinishAction.exported);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Texto exportado'),
          content: SelectableText('Archivo guardado en:\n$filePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      await _showOutputFailureDialog(error);
    }
  }

  Future<Directory> _resolveExportDirectoryPath() async {
    if (_exportDirectoryPath != null && _exportDirectoryPath!.isNotEmpty) {
      final directory = Directory(_exportDirectoryPath!);
      if (await directory.exists()) {
        return directory;
      }
    }

    if (!kIsWeb) {
      final downloadsDirectory = await getDownloadsDirectory();
      if (downloadsDirectory != null) {
        return downloadsDirectory;
      }
    }

    return getApplicationDocumentsDirectory();
  }

  Future<void> _showOutputFailureDialog(Object error) async {
    if (!mounted) return;
    final message = error.toString();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('No fue posible completar la acción'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No fue posible recuperar todo el texto bíblico solicitado. Se continuará con el contenido escaneado.',
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveToHistory() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _savedToHistory) return;
    await _store.insert(CaptureRecord(
      createdAt: DateTime.now(),
      imagePath: _imagePath ?? '',
      recognizedText: text,
      references: _groupedRefs.map((r) => r.reference).toList(),
    ));
    await _loadHistory();
    if (!mounted) return;
    setState(() {
      _savedToHistory = true;
      _completedAction = _FinishAction.savedToHistory;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Guardado en historial')),
    );
  }

  Future<void> _pickTextFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    try {
      _textController.text = await File(path).readAsString();
      _advanceToReview();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo leer el archivo: $e')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    setState(() {
      _processing = true;
      _imagePath = path;
    });
    try {
      _textController.text = await _runOcr(path);
      _advanceToReview();
    } catch (e, st) {
      debugPrint('OCR error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('OCR falló: $e')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _openCamera() async {
    if (!_supportsCameraCapture) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cámara no disponible en esta plataforma.'),
          ),
        );
      }
      setState(() => _step = _WizardStep.chooseSource);
      return;
    }
    final imagePath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraCapturePage(),
        fullscreenDialog: true,
      ),
    );
    if (imagePath == null || !mounted) {
      setState(() => _step = _WizardStep.chooseSource);
      return;
    }
    setState(() {
      _processing = true;
      _imagePath = imagePath;
    });
    try {
      _textController.text = await _runOcr(imagePath);
      _advanceToReview();
    } catch (e, st) {
      debugPrint('OCR error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('OCR falló: $e')));
        setState(() => _step = _WizardStep.chooseSource);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<String> _runOcr(String imagePath) async {
    final prepared = await _prepareOcrImage(imagePath);
    try {
      if (!(Platform.isMacOS || Platform.isIOS)) return '';
      final result = await _ocrChannel.invokeMethod<String>(
        'recognizeTextFromPath',
        {'path': prepared.path},
      );
      return result?.trim() ?? '';
    } finally {
      if (prepared.temporary) {
        try {
          await File(prepared.path).delete();
        } on FileSystemException catch (_) {}
      }
    }
  }

  Future<({String path, bool temporary})> _prepareOcrImage(
    String sourcePath,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return (path: sourcePath, temporary: false);
    const cf = 0.9;
    final cw = (decoded.width * cf).round();
    final ch = (decoded.height * cf).round();
    final cx = ((decoded.width - cw) / 2).round();
    final cy = ((decoded.height - ch) / 2).round();
    final cropped =
        img.copyCrop(decoded, x: cx, y: cy, width: cw, height: ch);
    final gray = img.grayscale(cropped);
    final resized =
        gray.width < 1200 ? img.copyResize(gray, width: 1200) : gray;
    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final out = p.join(
      dir.path,
      'ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(out).writeAsBytes(img.encodeJpg(resized, quality: 95),
        flush: true);
    return (path: out, temporary: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useDesktop =
                _isDesktopPlatform || constraints.maxWidth >= 720;
            return useDesktop
                ? _buildDesktopLayout(context)
                : _buildMobileLayout(context);
          },
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final versionLabel = '$kAppTitle $kAppVersionLabel';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              versionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        _WizardTopBar(step: _step, onReset: _resetWizard),
        const Divider(height: 1),
        Expanded(
          child: _buildStepContent(context, isDesktop: false),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        _WizardSidebar(step: _step, onReset: _resetWizard),
        const VerticalDivider(width: 1),
        Expanded(
          child: _buildStepContent(context, isDesktop: true),
        ),
      ],
    );
  }

  Widget _buildStepContent(BuildContext context, {required bool isDesktop}) {
    return switch (_step) {
      _WizardStep.chooseSource => _ChooseSourceStep(
          cameraSupported: _supportsCameraCapture,
          onSelect: _selectSource,
        ),
      _WizardStep.acquireContent => _AcquireContentStep(
          source: _source ?? _WizardSource.text,
          textController: _textController,
          imagePath: _imagePath,
          processing: _processing,
          history: _history,
          onPickFile: _pickTextFile,
          onPickImage: _pickImage,
          onOpenCamera: _openCamera,
          onContinueText: _advanceToReview,
          onHistorySelect: (r) {
            _textController.text = r.recognizedText;
            _advanceToReview();
          },
        ),
      _WizardStep.reviewText => _ReviewTextStep(
          textController: _textController,
          onBack: () => setState(() => _step = _WizardStep.acquireContent),
          onContinue: _runDetection,
        ),
      _WizardStep.detectRefs => _DetectRefsStep(
          charCount: _textController.text.length,
          groupedRefs: _groupedRefs,
          detectionDuration: _detectionDuration,
          onBack: () => setState(() => _step = _WizardStep.reviewText),
          onContinue: _groupedRefs.isNotEmpty ? _goToExplore : null,
        ),
      _WizardStep.exploreRefs => _ExploreRefsStep(
          groupedRefs: _groupedRefs,
          currentRefIndex: _currentRefIndex,
          activeReference: _activeReference,
          bibleText: _bibleText,
          bibleMessage: _bibleMessage,
          loadingBibleText: _loadingBibleText,
          selectedBibleVersionId: _selectedBibleVersionId,
          copiedFeedbackVisible: _copiedFeedbackVisible,
          isDesktop: isDesktop,
          onRefSelected: _selectRef,
          onNavigate: _navigateRef,
          onBibleVersionChanged: _onBibleVersionChanged,
          onCopyBibleText: _copyBibleText,
          onBack: () => setState(() => _step = _WizardStep.detectRefs),
          onContinue: () => setState(() => _step = _WizardStep.finish),
        ),
      _WizardStep.finish => _FinishStep(
          refCount: _groupedRefs.length,
          savedToHistory: _savedToHistory,
          completedAction: _completedAction,
          includeBibleTextInOutput: _includeBibleTextInOutput,
          exportDirectoryPath: _exportDirectoryPath,
          onSaveToHistory: _saveToHistory,
          onCopyReferences: _copyAllReferences,
          onShareResult: _shareResult,
          onExportText: _exportText,
          onToggleIncludeBibleText: _toggleIncludeBibleText,
          onNewScan: _resetWizard,
        ),
    };
  }
}

// ============================================================
// Stepper components
// ============================================================

class _WizardTopBar extends StatelessWidget {
  const _WizardTopBar({required this.step, required this.onReset});
  final _WizardStep step;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final currentIndex = step.index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _WizardStep.values.length; i++) ...[
                    if (i > 0)
                      _StepConnector(completed: i <= currentIndex),
                    _StepCircle(
                      number: i + 1,
                      label: _WizardStep.values[i].label,
                      state: i < currentIndex
                          ? _StepState.completed
                          : i == currentIndex
                              ? _StepState.active
                              : _StepState.inactive,
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt_outlined),
            tooltip: 'Nuevo escaneo',
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _WizardSidebar extends StatelessWidget {
  const _WizardSidebar({required this.step, required this.onReset});
  final _WizardStep step;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIndex = step.index;
    return Container(
      width: 192,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_rounded,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$kAppTitle $kAppVersionLabel',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          for (int i = 0; i < _WizardStep.values.length; i++) ...[
            _VerticalStepItem(
              number: i + 1,
              label: _WizardStep.values[i].label,
              state: i < currentIndex
                  ? _StepState.completed
                  : i == currentIndex
                      ? _StepState.active
                      : _StepState.inactive,
            ),
            if (i < _WizardStep.values.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Container(
                  width: 2,
                  height: 18,
                  color: i < currentIndex
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_outlined, size: 16),
            label: const Text('Nuevo escaneo'),
          ),
        ],
      ),
    );
  }
}

enum _StepState { active, completed, inactive }

class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.number,
    required this.label,
    required this.state,
  });
  final int number;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isActive = state == _StepState.active;
    final isCompleted = state == _StepState.completed;
    final filled = isActive || isCompleted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? primary
                : theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: filled ? primary : theme.colorScheme.outline,
              width: isActive ? 2 : 1.5,
            ),
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, size: 16,
                    color: theme.colorScheme.onPrimary)
                : Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: filled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.bold : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.completed});
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 2,
      color: completed
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _VerticalStepItem extends StatelessWidget {
  const _VerticalStepItem({
    required this.number,
    required this.label,
    required this.state,
  });
  final int number;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isActive = state == _StepState.active;
    final isCompleted = state == _StepState.completed;
    final filled = isActive || isCompleted;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? primary
                : theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: filled ? primary : theme.colorScheme.outline,
              width: 1.5,
            ),
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, size: 14,
                    color: theme.colorScheme.onPrimary)
                : Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isActive
                  ? primary
                  : isCompleted
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.bold : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Step 1 — Choose Source
// ============================================================

class _ChooseSourceStep extends StatelessWidget {
  const _ChooseSourceStep({
    required this.cameraSupported,
    required this.onSelect,
  });
  final bool cameraSupported;
  final ValueChanged<_WizardSource> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Cómo quieres comenzar?',
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Elige una opción para importar tu contenido.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _SourceCard(
            icon: Icons.text_fields_rounded,
            title: 'Escribir o pegar texto',
            subtitle:
                'Escribe directamente o pega desde el portapapeles.',
            onTap: () => onSelect(_WizardSource.text),
          ),
          const SizedBox(height: 12),
          _SourceCard(
            icon: Icons.description_outlined,
            title: 'Abrir archivo de texto',
            subtitle: 'Selecciona un archivo .txt desde tu dispositivo.',
            onTap: () => onSelect(_WizardSource.file),
          ),
          const SizedBox(height: 12),
          _SourceCard(
            icon: Icons.image_outlined,
            title: 'Elegir una imagen',
            subtitle: 'Selecciona una imagen de tu galería.',
            onTap: () => onSelect(_WizardSource.image),
          ),
          if (cameraSupported) ...[
            const SizedBox(height: 12),
            _SourceCard(
              icon: Icons.camera_alt_outlined,
              title: 'Tomar fotografía',
              subtitle: 'Usa la cámara para capturar el texto.',
              onTap: () => onSelect(_WizardSource.camera),
            ),
          ],
          const SizedBox(height: 12),
          _SourceCard(
            icon: Icons.history_rounded,
            title: 'Historial de escaneos',
            subtitle: 'Revisa escaneos anteriores.',
            onTap: () => onSelect(_WizardSource.history),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: theme.colorScheme.onPrimaryContainer, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Step 2 — Acquire Content
// ============================================================

class _AcquireContentStep extends StatelessWidget {
  const _AcquireContentStep({
    required this.source,
    required this.textController,
    required this.imagePath,
    required this.processing,
    required this.history,
    required this.onPickFile,
    required this.onPickImage,
    required this.onOpenCamera,
    required this.onContinueText,
    required this.onHistorySelect,
  });
  final _WizardSource source;
  final TextEditingController textController;
  final String? imagePath;
  final bool processing;
  final List<CaptureRecord> history;
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final VoidCallback onOpenCamera;
  final VoidCallback onContinueText;
  final ValueChanged<CaptureRecord> onHistorySelect;

  @override
  Widget build(BuildContext context) {
    return switch (source) {
      _WizardSource.text => _TextInputContent(
          controller: textController,
          onContinue: onContinueText,
        ),
      _WizardSource.file => _FilePickerContent(
          processing: processing,
          onPickFile: onPickFile,
        ),
      _WizardSource.image => _ImagePickerContent(
          imagePath: imagePath,
          processing: processing,
          onPickImage: onPickImage,
        ),
      _WizardSource.camera => _CameraLoadingContent(processing: processing),
      _WizardSource.history => _HistoryListContent(
          history: history,
          onSelect: onHistorySelect,
        ),
    };
  }
}

class _TextInputContent extends StatelessWidget {
  const _TextInputContent(
      {required this.controller, required this.onContinue});
  final TextEditingController controller;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Escribe o pega el texto',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              key: const ValueKey('source-text-field'),
              controller: controller,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'Pega o escribe texto aquí…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => FilledButton.icon(
                onPressed:
                    controller.text.trim().isNotEmpty ? onContinue : null,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Continuar'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePickerContent extends StatelessWidget {
  const _FilePickerContent(
      {required this.processing, required this.onPickFile});
  final bool processing;
  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Selecciona un archivo .txt',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'El contenido se cargará automáticamente.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: processing ? null : onPickFile,
              icon: processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.file_open_outlined),
              label: Text(processing ? 'Procesando…' : 'Abrir archivo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePickerContent extends StatelessWidget {
  const _ImagePickerContent({
    required this.imagePath,
    required this.processing,
    required this.onPickImage,
  });
  final String? imagePath;
  final bool processing;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = imagePath != null && File(imagePath!).existsSync();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Selecciona una imagen',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          if (hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(imagePath!),
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined,
                      size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text('Sin imagen',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: processing ? null : onPickImage,
            icon: processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(hasImage
                    ? Icons.refresh_outlined
                    : Icons.photo_library_outlined),
            label: Text(processing
                ? 'Procesando OCR…'
                : hasImage
                    ? 'Cambiar imagen'
                    : 'Elegir imagen'),
          ),
          if (processing) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Extrayendo texto con OCR…',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _CameraLoadingContent extends StatelessWidget {
  const _CameraLoadingContent({required this.processing});
  final bool processing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            processing ? 'Procesando imagen…' : 'Abriendo cámara…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _HistoryListContent extends StatelessWidget {
  const _HistoryListContent({
    required this.history,
    required this.onSelect,
  });
  final List<CaptureRecord> history;
  final ValueChanged<CaptureRecord> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_outlined,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('Sin historial', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Tus escaneos guardados aparecerán aquí.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final record = history[index];
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => onSelect(record),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history_rounded,
                          size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        _formatTimestamp(record.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary),
                      ),
                      const Spacer(),
                      if (record.references.isNotEmpty)
                        Chip(
                          label: Text('${record.references.length} citas'),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          labelStyle: theme.textTheme.labelSmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    record.recognizedText.isEmpty
                        ? 'Sin texto reconocido.'
                        : record.recognizedText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// Step 3 — Review Text
// ============================================================

class _ReviewTextStep extends StatefulWidget {
  const _ReviewTextStep({
    required this.textController,
    required this.onBack,
    required this.onContinue,
  });
  final TextEditingController textController;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  State<_ReviewTextStep> createState() => _ReviewTextStepState();
}

class _ReviewTextStepState extends State<_ReviewTextStep> {
  bool _showPreview = true;
  List<VerseMatch> _previewMatches = const [];

  @override
  void initState() {
    super.initState();
    widget.textController.addListener(_onTextChanged);
    _refreshPreview();
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (_showPreview) {
      setState(() => _showPreview = false);
    }
  }

  void _refreshPreview() {
    final text = widget.textController.text;
    setState(() {
      _previewMatches = extractVerseMatches(text);
      _showPreview = true;
    });
  }

  TextSpan _buildHighlightedPreview(String text) {
    final spans = <InlineSpan>[];
    final sorted = [..._previewMatches]..sort((a, b) => a.start.compareTo(b.start));
    var pos = 0;

    for (final match in sorted) {
      final start = match.start.clamp(0, text.length);
      final end = match.end.clamp(0, text.length);
      if (start >= end) continue;
      if (start > pos) {
        spans.add(TextSpan(text: text.substring(pos, start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: const TextStyle(
            color: Color(0xFFAD1457),
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0xFFF8BBD0),
          ),
        ),
      );
      pos = end;
    }

    if (pos < text.length) {
      spans.add(TextSpan(text: text.substring(pos)));
    }

    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final charCount = widget.textController.text.length;
    final previewText = widget.textController.text;
    final previewLabel = _previewMatches.length == 1
        ? '1 cita resaltada'
        : '${_previewMatches.length} citas resaltadas';
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Revisar el texto reconocido',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Edita cualquier parte si es necesario.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                onPressed: previewText.trim().isEmpty ? null : _refreshPreview,
                tooltip: 'Volver a revisar citas',
                icon: const Icon(Icons.visibility_outlined, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final useSplit = constraints.maxWidth >= 760;
              final previewPanel = _showPreview
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: theme.colorScheme.surfaceContainerLow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vista previa de citas bíblicas',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: SelectableText.rich(
                                _buildHighlightedPreview(previewText),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink();
              final editorField = Expanded(
                child: TextField(
                  controller: widget.textController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              );

              return SizedBox(
                height: 320,
                child: useSplit
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: previewPanel),
                          const SizedBox(width: 12),
                          editorField,
                        ],
                      )
                    : Column(
                        children: [
                          if (_showPreview) ...[
                            SizedBox(height: 180, child: previewPanel),
                            const SizedBox(height: 12),
                          ],
                          editorField,
                        ],
                      ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      '$charCount caracteres',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      previewText.trim().isEmpty || !_showPreview
                          ? '0 citas resaltadas'
                          : previewLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: widget.onBack,
                child: const Text('Atrás'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: charCount > 0 ? widget.onContinue : null,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Continuar'),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

// ============================================================
// Step 4 — Detect References
// ============================================================

class _DetectRefsStep extends StatelessWidget {
  const _DetectRefsStep({
    required this.charCount,
    required this.groupedRefs,
    required this.detectionDuration,
    required this.onBack,
    required this.onContinue,
  });
  final int charCount;
  final List<({String reference, int count})> groupedRefs;
  final Duration? detectionDuration;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDetecting = detectionDuration == null;
    if (isDetecting) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            groupedRefs.isEmpty
                ? 'No se encontraron citas'
                : '¡Encontramos ${groupedRefs.length} citas!',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Se han detectado posibles citas bíblicas.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: groupedRefs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text('Sin citas bíblicas detectadas.',
                            style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 400;
                      return wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    flex: 3,
                                    child: _RefCountList(
                                        refs: groupedRefs)),
                                const SizedBox(width: 16),
                                Expanded(
                                    flex: 2,
                                    child: _AnalysisSummaryCard(
                                      charCount: charCount,
                                      refCount: groupedRefs.length,
                                      duration: detectionDuration!,
                                    )),
                              ],
                            )
                          : Column(
                              children: [
                                _AnalysisSummaryCard(
                                  charCount: charCount,
                                  refCount: groupedRefs.length,
                                  duration: detectionDuration!,
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                    child: _RefCountList(
                                        refs: groupedRefs)),
                              ],
                            );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton(onPressed: onBack, child: const Text('Atrás')),
              const Spacer(),
              FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Continuar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RefCountList extends StatelessWidget {
  const _RefCountList({required this.refs});
  final List<({String reference, int count})> refs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      itemCount: refs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final ref = refs[i];
        return ListTile(
          dense: true,
          title: Text(ref.reference, style: theme.textTheme.bodyMedium),
          trailing: ref.count > 1 ? Badge.count(count: ref.count) : null,
        );
      },
    );
  }
}

class _AnalysisSummaryCard extends StatelessWidget {
  const _AnalysisSummaryCard({
    required this.charCount,
    required this.refCount,
    required this.duration,
  });
  final int charCount;
  final int refCount;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumen del análisis',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _SummaryRow(
              icon: Icons.text_snippet_outlined,
              label: 'Texto analizado',
              value: '$charCount caracteres',
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              icon: Icons.menu_book_outlined,
              label: 'Citas encontradas',
              value: '$refCount',
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              icon: Icons.timer_outlined,
              label: 'Tiempo de análisis',
              value: duration.inMilliseconds < 1000
                  ? '${duration.inMilliseconds}ms'
                  : '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s',
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              Text(value,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Step 5 — Explore References
// ============================================================

class _ExploreRefsStep extends StatelessWidget {
  const _ExploreRefsStep({
    required this.groupedRefs,
    required this.currentRefIndex,
    required this.activeReference,
    required this.bibleText,
    required this.bibleMessage,
    required this.loadingBibleText,
    required this.selectedBibleVersionId,
    required this.copiedFeedbackVisible,
    required this.isDesktop,
    required this.onRefSelected,
    required this.onNavigate,
    required this.onBibleVersionChanged,
    required this.onCopyBibleText,
    required this.onBack,
    required this.onContinue,
  });

  final List<({String reference, int count})> groupedRefs;
  final int currentRefIndex;
  final String? activeReference;
  final String? bibleText;
  final String bibleMessage;
  final bool loadingBibleText;
  final int selectedBibleVersionId;
  final bool copiedFeedbackVisible;
  final bool isDesktop;
  final void Function(String, int) onRefSelected;
  final ValueChanged<int> onNavigate;
  final ValueChanged<int?> onBibleVersionChanged;
  final VoidCallback onCopyBibleText;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (activeReference != null)
                      Flexible(
                        child: Text(
                          activeReference!,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(width: 8),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: selectedBibleVersionId,
                        isDense: true,
                        style: theme.textTheme.titleSmall,
                        items: kSupportedBibleVersions
                            .where((v) => v.enabled)
                            .map(
                              (v) => DropdownMenuItem<int>(
                                value: v.id,
                                child: Text(v.code),
                              ),
                            )
                            .toList(),
                        onChanged: onBibleVersionChanged,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: bibleText != null ? onCopyBibleText : null,
                tooltip: 'Copiar versículo',
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: copiedFeedbackVisible
                      ? const Icon(
                          key: ValueKey('check'),
                          Icons.check_circle,
                          color: Colors.green,
                        )
                      : const Icon(
                          key: ValueKey('copy'),
                          Icons.content_copy_outlined,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Content area
          Expanded(
            child: isDesktop
                ? Row(
                    children: [
                      SizedBox(
                        width: 180,
                        child: _RefListPanel(
                          refs: groupedRefs,
                          currentIndex: currentRefIndex,
                          onSelect: onRefSelected,
                        ),
                      ),
                      const VerticalDivider(width: 16),
                      Expanded(
                        child: _VersePanel(
                          bibleText: bibleText,
                          bibleMessage: bibleMessage,
                          loading: loadingBibleText,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _VersePanel(
                          bibleText: bibleText,
                          bibleMessage: bibleMessage,
                          loading: loadingBibleText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 56,
                        child: _RefChipsPanel(
                          refs: groupedRefs,
                          currentIndex: currentRefIndex,
                          onSelect: onRefSelected,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          // Navigation + action row
          Row(
            children: [
              OutlinedButton(onPressed: onBack, child: const Text('Atrás')),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: currentRefIndex > 0 ? () => onNavigate(-1) : null,
              ),
              SizedBox(
                width: 96,
                child: Text(
                  '${currentRefIndex + 1} de ${groupedRefs.length}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: currentRefIndex < groupedRefs.length - 1
                    ? () => onNavigate(1)
                    : null,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Finalizar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RefListPanel extends StatelessWidget {
  const _RefListPanel({
    required this.refs,
    required this.currentIndex,
    required this.onSelect,
  });
  final List<({String reference, int count})> refs;
  final int currentIndex;
  final void Function(String, int) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      itemCount: refs.length,
      itemBuilder: (context, i) {
        final ref = refs[i];
        final isActive = i == currentIndex;
        return ListTile(
          dense: true,
          selected: isActive,
          selectedColor: theme.colorScheme.primary,
          selectedTileColor: theme.colorScheme.primaryContainer
              .withValues(alpha: 0.3),
          title: Text(ref.reference, style: theme.textTheme.bodySmall),
          onTap: () => onSelect(ref.reference, i),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        );
      },
    );
  }
}

class _RefChipsPanel extends StatelessWidget {
  const _RefChipsPanel({
    required this.refs,
    required this.currentIndex,
    required this.onSelect,
  });
  final List<({String reference, int count})> refs;
  final int currentIndex;
  final void Function(String, int) onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: refs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final ref = refs[i];
        final isActive = i == currentIndex;
        return FilterChip(
          selected: isActive,
          label: Text(ref.reference),
          onSelected: (_) => onSelect(ref.reference, i),
        );
      },
    );
  }
}

class _VersePanel extends StatelessWidget {
  const _VersePanel({
    required this.bibleText,
    required this.bibleMessage,
    required this.loading,
  });
  final String? bibleText;
  final String bibleMessage;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final text = bibleText;
    return Container(
      width: double.infinity,
      height: double.infinity,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: text != null
            ? Text(
                '"$text"',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontSize: 18,
                  fontFamily: 'Times New Roman',
                  fontFamilyFallback: const ['Times', 'Noto Serif', 'serif'],
                  height: 1.6,
                ),
              )
            : Text(
                bibleMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

// ============================================================
// Step 6 — Finish
// ============================================================

class _FinishStep extends StatelessWidget {
  const _FinishStep({
    required this.refCount,
    required this.savedToHistory,
    required this.completedAction,
    required this.includeBibleTextInOutput,
    required this.exportDirectoryPath,
    required this.onSaveToHistory,
    required this.onCopyReferences,
    required this.onShareResult,
    required this.onExportText,
    required this.onToggleIncludeBibleText,
    required this.onNewScan,
  });
  final int refCount;
  final bool savedToHistory;
  final _FinishAction completedAction;
  final bool includeBibleTextInOutput;
  final String? exportDirectoryPath;
  final VoidCallback onSaveToHistory;
  final VoidCallback onCopyReferences;
  final VoidCallback onShareResult;
  final VoidCallback onExportText;
  final ValueChanged<bool> onToggleIncludeBibleText;
  final VoidCallback onNewScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.shade100,
            ),
            child: Icon(Icons.check_circle_rounded,
                color: Colors.green.shade700, size: 52),
          ),
          const SizedBox(height: 20),
          Text('¡Escaneo completado!',
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Se encontraron $refCount citas bíblicas.',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: includeBibleTextInOutput,
            onChanged: onToggleIncludeBibleText,
            title: const Text('Incluir texto bíblico en resultados'),
            subtitle: const Text('Se añadirá el texto bíblico de cada cita cuando sea posible.'),
          ),
          if (exportDirectoryPath != null && exportDirectoryPath!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Carpeta exportación: $exportDirectoryPath',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 24),
          _FinishCard(
            icon: Icons.save_outlined,
            title: 'Guardar en historial',
            subtitle: savedToHistory
                ? 'Guardado correctamente.'
                : 'Guarda este resultado para consultarlo después.',
            onTap: savedToHistory ? null : onSaveToHistory,
            trailing: savedToHistory
                ? Icon(Icons.check_circle, color: Colors.green.shade600)
                : null,
          ),
          const SizedBox(height: 12),
          _FinishCard(
            icon: Icons.copy_outlined,
            title: 'Copiar citas',
            subtitle: 'Copia solo las citas bíblicas encontradas y su texto bíblico si está activado.',
            onTap: onCopyReferences,
            trailing: completedAction == _FinishAction.copiedCitations
                ? Icon(Icons.check_circle, color: Colors.green.shade600)
                : null,
          ),
          const SizedBox(height: 12),
          _FinishCard(
            icon: Icons.share_outlined,
            title: 'Copiar resultado escaneado',
            subtitle: 'Copia solo el texto escaneado y su texto bíblico si está activado.',
            onTap: onShareResult,
            trailing: completedAction == _FinishAction.copiedScannedResult
                ? Icon(Icons.check_circle, color: Colors.green.shade600)
                : null,
          ),
          const SizedBox(height: 12),
          _FinishCard(
            icon: Icons.download_outlined,
            title: 'Exportar texto',
            subtitle: 'Exporta el texto escaneado con citas y texto bíblico opcional en un archivo .txt.',
            onTap: onExportText,
            trailing: completedAction == _FinishAction.exported
                ? Icon(Icons.check_circle, color: Colors.green.shade600)
                : null,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNewScan,
              icon: const Icon(Icons.restart_alt_outlined),
              label: const Text('Nuevo escaneo'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinishCard extends StatelessWidget {
  const _FinishCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
