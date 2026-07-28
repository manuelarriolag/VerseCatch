import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

enum InputSource { text, image, camera }

const bool kEnableHistoryFeature = false;
const bool kShowBanner = false;
const String kNoBibleTextMessage =
    'Select a highlighted reference to view biblical text.';

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
      title: 'Verse Catch',
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

  @override
  void initState() {
    super.initState();
    _loadHistory();
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
    final activeReference = _activeReference;
    if (activeReference == null) return null;
    return lookupBibleText(activeReference);
  }

  void _syncBibleText() {
    final bibleText = _getSelectedBibleText();
    final text = (bibleText == null || bibleText.isEmpty)
        ? kNoBibleTextMessage
        : bibleText;
    if (_bibleTextController.text == text) return;
    _bibleTextController.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  Future<void> _copySelectedBibleText() async {
    final referenceText = _activeReference;
    final bibleText = _getSelectedBibleText();
    if (referenceText == null || bibleText == null || bibleText.isEmpty) return;

    final clipboardText = '$referenceText\n"$bibleText"';
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
     if (!Platform.isMacOS) {
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
        references: _verseMatches.map((vm) => vm.reference).toSet().toList(),
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
    final canDone = _isEditing && _verseMatches.isNotEmpty;
    final canEdit = !_isEditing;
    final footerVisible =
        _textController.text.trim().isNotEmpty && _activeReference != null;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const dividerHeight = 8.0;
            final headerHeight = kShowBanner
                ? (constraints.maxHeight * 0.42).clamp(280.0, 360.0)
                : (constraints.maxHeight * 0.36).clamp(248.0, 320.0);
            final contentHeight = (constraints.maxHeight - headerHeight - 16.0)
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
                : (panelsHeight / (defaultBodyMinHeight + defaultFooterMinHeight))
                    .clamp(0.0, 1.0);
            final bodyMinHeight =
                (defaultBodyMinHeight * minHeightsScale).clamp(
              compactBodyMinFloor,
              defaultBodyMinHeight,
            );
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
              final bodyShare = effectiveBodyMinHeight / minimumPanelsHeight;
              effectiveBodyMinHeight = panelsHeight * bodyShare;
              effectiveFooterMinHeight = panelsHeight - effectiveBodyMinHeight;
            }
            final bodyMaxHeight = (panelsHeight - effectiveFooterMinHeight).clamp(
              0.0,
              double.infinity,
            );
            final bodyLowerBound = effectiveBodyMinHeight.clamp(0.0, bodyMaxHeight);

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
                (_getSelectedBibleText()?.isNotEmpty ?? false);

            return Column(
              children: [
                SizedBox(
                  height: headerHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text('Verse Catch', style: theme.textTheme.titleLarge),
                            const Spacer(),
                            if (kEnableHistoryFeature && hasText)
                              IconButton(
                                icon: const Icon(Icons.save_outlined),
                                tooltip: 'Save to history',
                                onPressed: _processing ? null : _saveCapture,
                              ),
                            IconButton(
                              key: const ValueKey('reset-button'),
                              icon: const Icon(Icons.restart_alt_outlined),
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
                              child: Text(
                                'Source text',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: canEdit ? _switchToEditMode : null,
                              icon: const Icon(Icons.edit_outlined, size: 18),
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
                        Expanded(
                          child: _buildBodyEditor(theme),
                        ),
                      ],
                    ),
                  ),
                ),
                if (footerVisible) ...[
                  GestureDetector(
                    onVerticalDragUpdate: (details) {
                      if (panelsHeight <= 0) return;
                      setState(() {
                        final adjusted = _bodyRatio +
                            (details.delta.dy / panelsHeight).clamp(-0.04, 0.04);
                        _bodyRatio = adjusted.clamp(0.35, 0.8);
                      });
                    },
                    child: SizedBox(
                      height: dividerHeight,
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
                  SizedBox(
                    height: footerHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                           Row(
                             children: [
                               Expanded(
                                 child: Text(
                                   'Biblical text',
                                   style: theme.textTheme.titleMedium,
                                 ),
                               ),
                               IconButton.filledTonal(
                                 key: const ValueKey('copy-bible-text-button'),
                                 onPressed: _activeReference == null
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
                                   ? theme.textTheme.bodyMedium
                                   : theme.textTheme.bodyMedium?.copyWith(
                                       color: theme.colorScheme.onSurfaceVariant,
                                     ),
                               decoration: InputDecoration(
                                 border: const OutlineInputBorder(),
                                 labelText: _activeReference ?? 'No reference selected',
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
                  ?                   _RichTextViewer(
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
          Text(
            'Recent scans',
            style: theme.textTheme.titleMedium,
          ),
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
    required this.onSourceChanged,
    required this.onPickFile,
    required this.onPickImage,
    required this.onOpenCamera,
  });

  final InputSource selected;
  final bool processing;
  final String? lastImagePath;
  final bool compactVertical;
  final ValueChanged<InputSource> onSourceChanged;
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final VoidCallback onOpenCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  final isCompact = constraints.maxWidth < 420 || compactVertical;
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
                                padding: WidgetStateProperty.resolveWith((states) {
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
                                ButtonSegment(
                                  value: InputSource.camera,
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  label: Text(
                                    isCompact ? 'Cam' : 'Camera',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              selected: {selected},
                              onSelectionChanged: (s) => onSourceChanged(s.first),
                            ),
                            SizedBox(height: controlsSpacing),
                            SizedBox(
                              width: double.infinity,
                              child: _buildActions(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _buildPreview(context, isCompact),
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

  Widget _buildActions(BuildContext context) {
    switch (selected) {
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

  Widget _buildPreview(BuildContext context, bool isCompact) {
    final theme = Theme.of(context);
    final previewHeight = isCompact ? 112.0 : 140.0;
    final previewIconSize = isCompact ? 30.0 : 36.0;
    final previewPadding = isCompact ? 10.0 : 12.0;
    final previewRadius = isCompact ? 10.0 : 12.0;

    switch (selected) {
      case InputSource.text:
        return Container(
          height: previewHeight,
          padding: EdgeInsets.all(previewPadding),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
          return ClipRRect(
            borderRadius: BorderRadius.circular(previewRadius),
            child: Image.file(
              File(lastImagePath!),
              height: previewHeight,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          );
        }

        return Container(
          height: previewHeight,
          padding: EdgeInsets.all(previewPadding),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
                selected == InputSource.camera ? 'No photo yet' : 'No image yet',
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
    final sorted = [...verseMatches]..sort((a, b) => a.start.compareTo(b.start));
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

  return references.toList(growable: false);
}

// ---------------------------------------------------------------------------
// Biblical text lookup
// ---------------------------------------------------------------------------

String? lookupBibleText(String reference) {
  final match = RegExp(
    r'^(.*)\s+(\d{1,3})\s*:\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?$',
  ).firstMatch(reference.trim());
  if (match == null) return null;

  final book = _canonicalBookKey(match.group(1)!);
  final chapter = match.group(2)!;
  final verse = match.group(3)!;
  final verseEnd = match.group(4);
  final suffix = verseEnd == null ? '$chapter:$verse' : '$chapter:$verse-$verseEnd';
  final key = '$book:$suffix'.toLowerCase();
  return _kBibleTextByReference[key];
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
    default:
      return normalized;
  }
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
  'revelation',
  'rev',
};

const _kBibleTextByReference = <String, String>{
  'john:3:16': 'For God so loved the world that he gave his one and only Son, '
      'that whoever believes in him shall not perish but have eternal life.',
  'romans:8:28': 'And we know that in all things God works for the good of '
      'those who love him, who have been called according to his purpose.',
  '1cor:13:4-7': 'Love is patient, love is kind. It does not envy, it does '
      'not boast, it is not proud. It does not dishonor others, it is not self-seeking, '
      'it is not easily angered, it keeps no record of wrongs. Love does not delight in evil '
      'but rejoices with the truth. It always protects, always trusts, always hopes, always perseveres.',
  'philippians:4:13': 'I can do all this through him who gives me strength.',
  'ephesians:3:3': 'By revelation, the mystery was made known to me.',
  'psalm:23:1': 'The Lord is my shepherd; I shall not want.',
  'proverbs:3:5-6': 'Trust in the Lord with all your heart and lean not on your own understanding; '
      'in all your ways submit to him, and he will make your paths straight.',
  'jeremiah:29:11': 'For I know the plans I have for you, declares the Lord, plans for welfare '
      'and not for evil, to give you a future and a hope.',
  'isaiah:40:31': 'But those who hope in the Lord will renew their strength. They will soar on wings like eagles.',
  'joshua:1:9': 'Have I not commanded you? Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.',
  'matthew:5:16': 'Let your light shine before others, that they may see your good deeds and glorify your Father in heaven.',
};

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
        reference: '$book $chapter:$verse${verseEnd == null ? '' : '-$verseEnd'}',
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
