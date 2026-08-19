part of '../main.dart';

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
