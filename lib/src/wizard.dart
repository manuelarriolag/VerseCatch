part of '../main.dart';

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

enum _OcrVisualState { idle, scanning, completed, exiting, failed }

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
  const WizardHomePage({
    super.key,
    required this.bibleTextLookup,
    required this.imageFilePicker,
    this.ocrTextRecognizer,
  });
  final BibleTextLookup bibleTextLookup;
  final ImageFilePicker imageFilePicker;
  final OcrTextRecognizer? ocrTextRecognizer;

  @override
  State<WizardHomePage> createState() => _WizardHomePageState();
}

class _WizardHomePageState extends State<WizardHomePage> {
  final _store = VerseCaptureStore.instance;
  static const _ocrChannel = MethodChannel('versecatch/ocr');
  static const _minimumScanDuration = Duration(seconds: 6);
  static const _scanCompletionHoldDuration = Duration(milliseconds: 400);
  static const _minimumDetectionVisualDuration = Duration(milliseconds: 2200);
  static const _detectionCompletionHoldDuration = Duration(milliseconds: 350);
  static const _stepSkeletonDuration = Duration(milliseconds: 180);

  _WizardStep _step = _WizardStep.chooseSource;
  final Set<_WizardStep> _completedSteps = <_WizardStep>{};
  _WizardSource? _source;

  final _textController = TextEditingController();
  String? _imagePath;
  bool _processing = false;
  _OcrVisualState _ocrVisualState = _OcrVisualState.idle;
  bool _ocrFinished = false;
  String? _ocrErrorMessage;

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
  bool _reduceMotionEnabled = false;
  List<ExportHistoryItem> _recentExports = const [];
  int _imageQuarterTurns = 0;
  Rect _imageCropRect = const Rect.fromLTWH(0, 0, 1, 1);
  bool _showCompactRefsView = true;

  List<CaptureRecord> _history = const [];
  bool _savedToHistory = false;
  _FinishAction _completedAction = _FinishAction.none;
  Duration? _detectionDuration;
  bool _isDetectingReferences = false;
  _OcrVisualState _reviewDetectionVisualState = _OcrVisualState.idle;
  bool _showStepSkeleton = false;
  Timer? _stepSkeletonTimer;

  bool get _supportsCameraCapture =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

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
    _stepSkeletonTimer?.cancel();
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
    final reduceMotion = await _store.reduceMotionEnabled();
    final exports = await _store.recentExports(limit: 5);
    if (!mounted) return;
    setState(() {
      _includeBibleTextInOutput = includeBibleText;
      _exportDirectoryPath = exportDirectory;
      _reduceMotionEnabled = reduceMotion;
      _recentExports = exports;
    });
  }

  Duration _motionDuration(Duration duration) {
    if (_reduceMotionEnabled) return Duration.zero;
    return duration;
  }

  BibleVersionOption _selectedBibleVersionOption() {
    return kSupportedBibleVersions.firstWhere(
      (version) => version.id == _selectedBibleVersionId,
      orElse: () => kSupportedBibleVersions.first,
    );
  }

  void _resetWizard() {
    _textController.clear();
    _stepSkeletonTimer?.cancel();
    setState(() {
      _step = _WizardStep.chooseSource;
      _completedSteps.clear();
      _source = null;
      _imagePath = null;
      _processing = false;
      _ocrVisualState = _OcrVisualState.idle;
      _ocrFinished = false;
      _ocrErrorMessage = null;
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
      _isDetectingReferences = false;
      _reviewDetectionVisualState = _OcrVisualState.idle;
      _showStepSkeleton = false;
      _imageQuarterTurns = 0;
      _imageCropRect = const Rect.fromLTWH(0, 0, 1, 1);
      _showCompactRefsView = true;
    });
    _loadHistory();
  }

  void _goToStep(
    _WizardStep next, {
    Set<_WizardStep> complete = const <_WizardStep>{},
    VoidCallback? mutate,
  }) {
    if (next == _step && complete.isEmpty && mutate == null) return;

    _stepSkeletonTimer?.cancel();

    setState(() {
      mutate?.call();
      _completedSteps.addAll(complete);
      _step = next;
      _showStepSkeleton = !_reduceMotionEnabled;
    });

    if (!_showStepSkeleton) return;
    _stepSkeletonTimer = Timer(_stepSkeletonDuration, () {
      if (!mounted) return;
      setState(() => _showStepSkeleton = false);
    });
  }

  void _selectSource(_WizardSource source) {
    _goToStep(
      _WizardStep.acquireContent,
      complete: const <_WizardStep>{_WizardStep.chooseSource},
      mutate: () => _source = source,
    );
    if (source == _WizardSource.camera) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
    }
  }

  void _advanceToReview() {
    _goToStep(
      _WizardStep.reviewText,
      complete: const <_WizardStep>{_WizardStep.acquireContent},
    );
  }

  void _navigateToStep(_WizardStep step) {
    if (step == _step || !_completedSteps.contains(step)) return;
    _goToStep(step);
    if (step == _WizardStep.exploreRefs && _activeReference != null) {
      _loadBibleText();
    }
  }

  Future<void> _runDetection() async {
    if (_isDetectingReferences) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final visualStart = DateTime.now();
    final detectionStart = DateTime.now();

    List<({String reference, int count})> grouped = const [];
    String? firstReference;

    setState(() {
      _completedSteps.add(_WizardStep.reviewText);
      _isDetectingReferences = true;
      _reviewDetectionVisualState = _OcrVisualState.scanning;
    });

    try {
      final matches = await Future<List<VerseMatch>>.microtask(
        () => extractVerseMatches(text),
      );
      final counts = <String, int>{};
      for (final m in matches) {
        counts[m.reference] = (counts[m.reference] ?? 0) + 1;
      }
      grouped = counts.entries
          .map((e) => (reference: e.key, count: e.value))
          .toList(growable: false);
      if (grouped.isNotEmpty) {
        firstReference = grouped.first.reference;
      }
    } finally {
      final elapsedVisual = DateTime.now().difference(visualStart);
      final remaining =
          _motionDuration(_minimumDetectionVisualDuration) - elapsedVisual;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    }

    if (!mounted) return;

    final duration = DateTime.now().difference(detectionStart);

    setState(() {
      _reviewDetectionVisualState = _OcrVisualState.completed;
      _groupedRefs = grouped;
      _detectionDuration = duration;
      if (firstReference != null) {
        _activeReference = firstReference;
        _currentRefIndex = 0;
      }
    });

    await Future<void>.delayed(
      _motionDuration(_detectionCompletionHoldDuration),
    );
    if (!mounted) return;

    setState(() => _reviewDetectionVisualState = _OcrVisualState.exiting);

    await Future<void>.delayed(
      _motionDuration(_detectionCompletionHoldDuration),
    );
    if (!mounted) return;

    setState(() {
      _isDetectingReferences = false;
      _reviewDetectionVisualState = _OcrVisualState.idle;
    });
    _goToStep(_WizardStep.detectRefs);
  }

  void _goToExplore() {
    _goToStep(
      _WizardStep.exploreRefs,
      complete: const <_WizardStep>{_WizardStep.detectRefs},
    );
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
    final newIndex = (_currentRefIndex + delta).clamp(
      0,
      _groupedRefs.length - 1,
    );
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
        _bibleText = (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
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

  Future<void> _toggleReduceMotion(bool value) async {
    setState(() => _reduceMotionEnabled = value);
    await _store.setReduceMotionEnabled(value);
  }

  void _rotateSelectedImage() {
    setState(() => _imageQuarterTurns = (_imageQuarterTurns + 1) % 4);
  }

  Future<void> _refreshExportHistory() async {
    final exports = await _store.recentExports(limit: 5);
    if (!mounted) return;
    setState(() => _recentExports = exports);
  }

  void _toggleExploreViewMode(bool compactView) {
    setState(() => _showCompactRefsView = compactView);
  }

  Future<void> _openCropDialog() async {
    final path = _imagePath;
    if (path == null || !File(path).existsSync()) return;
    Rect draft = _imageCropRect;

    final result = await showDialog<({Rect rect, bool applyCrop})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Rect normalize(Rect value) {
              const minSize = 0.12;
              final width = value.width.clamp(minSize, 1.0);
              final height = value.height.clamp(minSize, 1.0);
              final left = value.left.clamp(0.0, 1.0 - width);
              final top = value.top.clamp(0.0, 1.0 - height);
              return Rect.fromLTWH(left, top, width, height);
            }

            void updateRect(Rect value) {
              setDialogState(() => draft = normalize(value));
            }

            final media = MediaQuery.of(context);
            final compactLayout =
                media.size.width < 420 || media.size.height < 760;
            final compactActions = compactLayout || media.size.width < 390;
            final dialogWidth = min(560.0, media.size.width - 20);
            final dialogHeight = compactLayout
                ? min(720.0, media.size.height - 28)
                : min(760.0, media.size.height - 64);

            return Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: compactLayout ? 10 : 24,
                vertical: compactLayout ? 12 : 24,
              ),
              child: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compactLayout ? 12 : 16,
                    compactLayout ? 10 : 14,
                    compactLayout ? 12 : 16,
                    compactLayout ? 10 : 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Recortar imagen',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Arrastra dentro del recuadro para moverlo. Usa las esquinas y selectores laterales para ajustar el área.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _CropSelectionPreview(
                            imagePath: path,
                            cropRect: draft,
                            onChanged: updateRect,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OverflowBar(
                        spacing: 8,
                        overflowSpacing: 8,
                        alignment: MainAxisAlignment.end,
                        overflowAlignment: OverflowBarAlignment.end,
                        children: [
                          IconButton.filledTonal(
                            onPressed: () =>
                                updateRect(const Rect.fromLTWH(0, 0, 1, 1)),
                            tooltip: 'Restablecer recorte',
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                          if (compactActions)
                            IconButton(
                              tooltip: 'Cancelar',
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            )
                          else
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Cancelar'),
                            ),
                          if (compactActions)
                            FilledButton.tonal(
                              key: const ValueKey('apply-crop-selection'),
                              onPressed: () => Navigator.of(
                                dialogContext,
                              ).pop((rect: draft, applyCrop: true)),
                              child: const Icon(Icons.content_cut_rounded),
                            )
                          else
                            FilledButton.tonalIcon(
                              key: const ValueKey('apply-crop-selection'),
                              onPressed: () => Navigator.of(
                                dialogContext,
                              ).pop((rect: draft, applyCrop: true)),
                              icon: const Icon(Icons.content_cut_rounded),
                              label: const Text('Aplicar recorte'),
                            ),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(
                              dialogContext,
                            ).pop((rect: draft, applyCrop: false)),
                            icon: const Icon(Icons.check),
                            label: const Text('Continuar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;
    if (result.applyCrop) {
      await _applyCropAndReplacePreview(
        sourcePath: path,
        cropRect: result.rect,
      );
      return;
    }
    setState(() => _imageCropRect = result.rect);
  }

  Future<void> _retryExportFromHistory(ExportHistoryItem item) async {
    final path = item.filePath.trim();
    if (path.isEmpty) return;
    await _exportText(
      presetDirectoryPath: p.dirname(path),
      presetFileName: p.basename(path),
    );
  }

  Future<void> _applyCropAndReplacePreview({
    required String sourcePath,
    required Rect cropRect,
  }) async {
    try {
      final croppedPath = await _buildCroppedImageSource(
        sourcePath: sourcePath,
        cropRect: cropRect,
      );
      if (!mounted) return;
      setState(() {
        _imagePath = croppedPath;
        _imageCropRect = const Rect.fromLTWH(0, 0, 1, 1);
        _imageQuarterTurns = 0;
        _ocrVisualState = _OcrVisualState.idle;
        _ocrFinished = false;
        _ocrErrorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recorte aplicado a la imagen')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aplicar el recorte: $error')),
      );
    }
  }

  Future<String> _buildCroppedImageSource({
    required String sourcePath,
    required Rect cropRect,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded =
        img.decodeImage(bytes) ?? await _decodeImageWithUiFallback(bytes);
    if (decoded == null) {
      throw StateError('No fue posible decodificar la imagen seleccionada.');
    }

    var working = decoded;
    if (_imageQuarterTurns != 0) {
      working = img.copyRotate(
        working,
        angle: (_imageQuarterTurns * 90).toDouble(),
      );
    }

    final left = cropRect.left.clamp(0.0, 1.0);
    final top = cropRect.top.clamp(0.0, 1.0);
    final width = cropRect.width.clamp(0.1, 1.0);
    final height = cropRect.height.clamp(0.1, 1.0);

    final x = (working.width * left).round().clamp(0, working.width - 1);
    final y = (working.height * top).round().clamp(0, working.height - 1);
    final w = (working.width * width).round().clamp(1, working.width - x);
    final h = (working.height * height).round().clamp(1, working.height - y);
    final cropped = img.copyCrop(working, x: x, y: y, width: w, height: h);

    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final out = p.join(
      dir.path,
      'crop_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(
      out,
    ).writeAsBytes(img.encodeJpg(cropped, quality: 95), flush: true);
    return out;
  }

  Future<img.Image?> _decodeImageWithUiFallback(Uint8List sourceBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(sourceBytes);
      final frame = await codec.getNextFrame();
      final pngBytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (pngBytes == null) return null;
      return img.decodeImage(pngBytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  Future<({String content, String? warning})>
  _buildOutputContentForCurrentSelection({required String sourceText}) async {
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
    final rateLimitWindowMs = kAppEnvironment.toLowerCase() == 'live'
        ? 1600
        : 900;
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
        debugPrint(
          'Bible text lookup failed for $reference: $error\n$stackTrace',
        );
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
    required Future<T> Function(
      void Function(int current, int total) updateProgress,
    )
    action,
  }) async {
    final startedAt = DateTime.now();
    final progressState =
        ValueNotifier<({int current, int total, bool completed})>((
          current: 0,
          total: 0,
          completed: false,
        ));
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
        progressState.value = (
          current: current,
          total: total,
          completed: false,
        );
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
      await Future<void>.delayed(
        _motionDuration(const Duration(milliseconds: 650)),
      );
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

  Future<bool> _confirmOutputPreview({
    required String sourceText,
    required String citationsText,
    required String finalText,
    String actionLabel = 'Continuar',
  }) async {
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        Widget buildPane(String text) {
          return Container(
            width: double.infinity,
            height: 260,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                text.trim().isEmpty ? '(Sin contenido)' : text,
                style: theme.textTheme.bodySmall,
              ),
            ),
          );
        }

        return AlertDialog(
          title: const Text('Vista previa del resultado'),
          content: SizedBox(
            width: 620,
            child: DefaultTabController(
              length: 3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Texto escaneado'),
                      Tab(text: 'Citas detectadas'),
                      Tab(text: 'Resultado final'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 270,
                    child: TabBarView(
                      children: [
                        buildPane(sourceText),
                        buildPane(citationsText),
                        buildPane(finalText),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    return accepted == true;
  }

  Future<void> _copyAllReferences() async {
    final text = _textController.text.trim();
    if (_groupedRefs.isEmpty || text.isEmpty) return;

    try {
      final version = _selectedBibleVersionOption();
      final payload =
          await _showActionProgressDialog<
            ({Map<String, String> biblicalTexts, String? warning})
          >(
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
      final scannedPreview = _textController.text.trim();
      final outputPreview = buildScannedResultClipboardContent(
        sourceText: scannedPreview,
        groupedRefs: _groupedRefs,
        includeBibleText: _includeBibleTextInOutput,
        biblicalTexts: payload.biblicalTexts,
        versionLabel: version.code,
      );
      final proceed = await _confirmOutputPreview(
        sourceText: scannedPreview,
        citationsText: clipboardContent,
        finalText: outputPreview,
        actionLabel: 'Copiar citas',
      );
      if (!proceed) return;
      await Clipboard.setData(ClipboardData(text: clipboardContent));
      if (!mounted) return;
      setState(() => _completedAction = _FinishAction.copiedCitations);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Citas copiadas')));
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
      final payload =
          await _showActionProgressDialog<
            ({Map<String, String> biblicalTexts, String? warning})
          >(
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
      final citationsPreview = buildCitationsClipboardContent(
        groupedRefs: _groupedRefs,
        includeBibleText: _includeBibleTextInOutput,
        biblicalTexts: payload.biblicalTexts,
        versionLabel: version.code,
      );
      final proceed = await _confirmOutputPreview(
        sourceText: text,
        citationsText: citationsPreview,
        finalText: clipboardContent,
        actionLabel: 'Copiar resultado',
      );
      if (!proceed) return;
      await Clipboard.setData(ClipboardData(text: clipboardContent));
      if (!mounted) return;
      setState(() => _completedAction = _FinishAction.copiedScannedResult);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resultado copiado al portapapeles')),
      );
    } catch (error) {
      if (!mounted) return;
      await _showOutputFailureDialog(error);
    }
  }

  Future<void> _exportText({
    String? presetDirectoryPath,
    String? presetFileName,
  }) async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final defaultDirectory = await _resolveExportDirectoryPath();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final defaultFileName = presetFileName ?? 'versecatch_$timestamp.txt';
    final fileNameController = TextEditingController(text: defaultFileName);
    final directoryController = TextEditingController(
      text: presetDirectoryPath ?? defaultDirectory.path,
    );
    String? validationError;
    final result = await showDialog<({String directoryPath, String fileName})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> submit() async {
              final rawFileName = fileNameController.text.trim();
              final rawDirectory = directoryController.text.trim();
              final invalidName = RegExp(r'[<>:"/\\|?*]').hasMatch(rawFileName);
              if (rawFileName.isEmpty) {
                setState(() {
                  validationError =
                      'El nombre del archivo no puede estar vacío.';
                });
                return;
              }
              if (invalidName) {
                setState(() {
                  validationError =
                      'El nombre contiene caracteres inválidos: < > : " / \\ | ? *';
                });
                return;
              }
              if (rawDirectory.isEmpty) {
                setState(() {
                  validationError = 'Selecciona una carpeta destino válida.';
                });
                return;
              }

              final candidateDir = Directory(rawDirectory);
              try {
                if (!await candidateDir.exists()) {
                  await candidateDir.create(recursive: true);
                }
                final probe = File(
                  p.join(
                    candidateDir.path,
                    '.versecatch_write_test_${DateTime.now().microsecondsSinceEpoch}',
                  ),
                );
                await probe.writeAsString('ok');
                await probe.delete();
              } catch (_) {
                setState(() {
                  validationError =
                      'La carpeta no es accesible para escritura. Elige otra ruta o usa Descargas.';
                });
                return;
              }

              if (!context.mounted) return;
              Navigator.of(
                dialogContext,
              ).pop((directoryPath: rawDirectory, fileName: rawFileName));
            }

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
                            validationError = null;
                          }),
                          child: const Text('Usar Descargas'),
                        ),
                      ],
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationError!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(onPressed: submit, child: const Text('Exportar')),
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

      final version = _selectedBibleVersionOption();
      final citationsPreview = buildCitationsClipboardContent(
        groupedRefs: _groupedRefs,
        includeBibleText: _includeBibleTextInOutput,
        biblicalTexts: const {},
        versionLabel: version.code,
      );
      final proceed = await _confirmOutputPreview(
        sourceText: text,
        citationsText: citationsPreview,
        finalText: buildResult.content,
        actionLabel: 'Exportar',
      );
      if (!proceed) {
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        return;
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
      await _store.pushExportHistory(
        ExportHistoryItem(
          timestamp: DateTime.now(),
          format: 'txt',
          filePath: filePath,
        ),
      );
      await _refreshExportHistory();
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
    await _store.insert(
      CaptureRecord(
        createdAt: DateTime.now(),
        imagePath: _imagePath ?? '',
        recognizedText: text,
        references: _groupedRefs.map((r) => r.reference).toList(),
      ),
    );
    await _loadHistory();
    if (!mounted) return;
    setState(() {
      _savedToHistory = true;
      _completedAction = _FinishAction.savedToHistory;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Guardado en historial')));
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
    final path = await widget.imageFilePicker();
    if (path == null) return;
    setState(() {
      _imagePath = path;
      _imageQuarterTurns = 0;
      _imageCropRect = const Rect.fromLTWH(0, 0, 1, 1);
      _ocrVisualState = _OcrVisualState.idle;
      _ocrFinished = false;
      _ocrErrorMessage = null;
    });
  }

  Future<void> _processSelectedImage() async {
    final path = _imagePath;
    if (path == null || !File(path).existsSync()) return;
    await _runImageOcrFlow(path: path, backToSourceOnFailure: false);
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
      _goToStep(_WizardStep.chooseSource);
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
      _goToStep(_WizardStep.chooseSource);
      return;
    }
    setState(() => _imagePath = imagePath);
    await _runImageOcrFlow(path: imagePath, backToSourceOnFailure: true);
  }

  Future<void> _runImageOcrFlow({
    required String path,
    required bool backToSourceOnFailure,
  }) async {
    final startedAt = DateTime.now();
    setState(() {
      _processing = true;
      _ocrFinished = false;
      _ocrErrorMessage = null;
      _ocrVisualState = _OcrVisualState.scanning;
    });

    String? recognizedText;
    Object? failure;

    try {
      recognizedText = await _performOcr(path);
    } catch (error, stackTrace) {
      failure = error;
      debugPrint('OCR error: $error\n$stackTrace');
    }

    final elapsed = DateTime.now().difference(startedAt);
    final remaining = _motionDuration(_minimumScanDuration) - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _processing = false;
        _ocrFinished = false;
        _ocrVisualState = _OcrVisualState.failed;
        _ocrErrorMessage = 'No fue posible reconocer el texto';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('OCR falló: $failure')));
      if (backToSourceOnFailure) {
        _goToStep(_WizardStep.chooseSource);
      }
      return;
    }

    setState(() {
      _textController.text = recognizedText ?? '';
      _processing = false;
      _ocrFinished = true;
      _ocrVisualState = _OcrVisualState.completed;
      _ocrErrorMessage = null;
    });

    await Future<void>.delayed(_motionDuration(_scanCompletionHoldDuration));
    if (!mounted) return;

    setState(() => _ocrVisualState = _OcrVisualState.exiting);
    await Future<void>.delayed(_motionDuration(_scanCompletionHoldDuration));
    if (!mounted) return;

    setState(() {
      _ocrVisualState = _OcrVisualState.idle;
      _ocrFinished = false;
    });
    _advanceToReview();
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

  Future<String> _performOcr(String imagePath) {
    final recognizer = widget.ocrTextRecognizer;
    if (recognizer != null) {
      return recognizer(imagePath);
    }
    return _runOcr(imagePath);
  }

  Future<({String path, bool temporary})> _prepareOcrImage(
    String sourcePath,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return (path: sourcePath, temporary: false);

    var working = decoded;
    if (_imageQuarterTurns != 0) {
      working = img.copyRotate(
        working,
        angle: (_imageQuarterTurns * 90).toDouble(),
      );
    }

    final left = _imageCropRect.left.clamp(0.0, 1.0);
    final top = _imageCropRect.top.clamp(0.0, 1.0);
    final width = _imageCropRect.width.clamp(0.1, 1.0);
    final height = _imageCropRect.height.clamp(0.1, 1.0);

    final x = (working.width * left).round().clamp(0, working.width - 1);
    final y = (working.height * top).round().clamp(0, working.height - 1);
    final w = (working.width * width).round().clamp(1, working.width - x);
    final h = (working.height * height).round().clamp(1, working.height - y);
    final cropped = img.copyCrop(working, x: x, y: y, width: w, height: h);

    final gray = img.grayscale(cropped);
    final resized = gray.width < 1200
        ? img.copyResize(gray, width: 1200)
        : gray;
    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final out = p.join(
      dir.path,
      'ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(
      out,
    ).writeAsBytes(img.encodeJpg(resized, quality: 95), flush: true);
    return (path: out, temporary: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useDesktop = constraints.maxWidth >= 720;
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
        _WizardTopBar(
          step: _step,
          completedSteps: _completedSteps,
          onStepSelected: _navigateToStep,
          onReset: _resetWizard,
        ),
        const Divider(height: 1),
        Expanded(child: _buildAnimatedStepContent(context, isDesktop: false)),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        _WizardSidebar(
          step: _step,
          completedSteps: _completedSteps,
          onStepSelected: _navigateToStep,
          onReset: _resetWizard,
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildAnimatedStepContent(context, isDesktop: true)),
      ],
    );
  }

  Widget _buildAnimatedStepContent(
    BuildContext context, {
    required bool isDesktop,
  }) {
    final duration = _motionDuration(const Duration(milliseconds: 170));
    final content = KeyedSubtree(
      key: ValueKey<String>('step-${_step.name}'),
      child: _buildStepContent(context, isDesktop: isDesktop),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: content,
        ),
        IgnorePointer(
          ignoring: !_showStepSkeleton,
          child: AnimatedOpacity(
            duration: _motionDuration(const Duration(milliseconds: 110)),
            opacity: _showStepSkeleton ? 1 : 0,
            child: _StepTransitionSkeleton(
              reduceMotionEnabled: _reduceMotionEnabled,
            ),
          ),
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
        imageQuarterTurns: _imageQuarterTurns,
        cropRect: _imageCropRect,
        processing: _processing,
        ocrVisualState: _ocrVisualState,
        ocrFinished: _ocrFinished,
        ocrErrorMessage: _ocrErrorMessage,
        reduceMotionEnabled: _reduceMotionEnabled,
        history: _history,
        onPickFile: _pickTextFile,
        onPickImage: _pickImage,
        onContinueImage: _processSelectedImage,
        onRotateImage: _rotateSelectedImage,
        onCropImage: _openCropDialog,
        onOpenCamera: _openCamera,
        onContinueText: _advanceToReview,
        onHistorySelect: (r) {
          _textController.text = r.recognizedText;
          _advanceToReview();
        },
      ),
      _WizardStep.reviewText => _ReviewTextStep(
        textController: _textController,
        detectingReferences: _isDetectingReferences,
        detectionVisualState: _reviewDetectionVisualState,
        reduceMotionEnabled: _reduceMotionEnabled,
        onBack: () => _goToStep(_WizardStep.acquireContent),
        onContinue: _runDetection,
      ),
      _WizardStep.detectRefs => _DetectRefsStep(
        charCount: _textController.text.length,
        groupedRefs: _groupedRefs,
        detectionDuration: _detectionDuration,
        onBack: () => _goToStep(_WizardStep.reviewText),
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
        compactView: _showCompactRefsView,
        reduceMotionEnabled: _reduceMotionEnabled,
        onRefSelected: _selectRef,
        onNavigate: _navigateRef,
        onToggleCompactView: _toggleExploreViewMode,
        onBibleVersionChanged: _onBibleVersionChanged,
        onCopyBibleText: _copyBibleText,
        onBack: () => _goToStep(_WizardStep.detectRefs),
        onContinue: () => _goToStep(
          _WizardStep.finish,
          complete: const <_WizardStep>{_WizardStep.exploreRefs},
        ),
      ),
      _WizardStep.finish => _FinishStep(
        refCount: _groupedRefs.length,
        savedToHistory: _savedToHistory,
        completedAction: _completedAction,
        includeBibleTextInOutput: _includeBibleTextInOutput,
        reduceMotionEnabled: _reduceMotionEnabled,
        recentExports: _recentExports,
        exportDirectoryPath: _exportDirectoryPath,
        onSaveToHistory: _saveToHistory,
        onCopyReferences: _copyAllReferences,
        onShareResult: _shareResult,
        onExportText: _exportText,
        onToggleIncludeBibleText: _toggleIncludeBibleText,
        onToggleReduceMotion: _toggleReduceMotion,
        onRetryExport: (item) {
          _retryExportFromHistory(item);
        },
        onNewScan: _resetWizard,
      ),
    };
  }
}

class _StepTransitionSkeleton extends StatefulWidget {
  const _StepTransitionSkeleton({required this.reduceMotionEnabled});

  final bool reduceMotionEnabled;

  @override
  State<_StepTransitionSkeleton> createState() =>
      _StepTransitionSkeletonState();
}

class _StepTransitionSkeletonState extends State<_StepTransitionSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (!widget.reduceMotionEnabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _StepTransitionSkeleton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotionEnabled == widget.reduceMotionEnabled) return;
    if (widget.reduceMotionEnabled) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.85,
    );

    return ColoredBox(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBar(
              widthFactor: 0.44,
              height: 18,
              baseColor: base,
              controller: _controller,
            ),
            const SizedBox(height: 10),
            _SkeletonBar(
              widthFactor: 0.72,
              height: 12,
              baseColor: base,
              controller: _controller,
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _SkeletonBar(
                widthFactor: 1,
                height: double.infinity,
                radius: 14,
                baseColor: base,
                controller: _controller,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SkeletonBar(
                    widthFactor: 1,
                    height: 42,
                    radius: 24,
                    baseColor: base,
                    controller: _controller,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SkeletonBar(
                    widthFactor: 1,
                    height: 42,
                    radius: 24,
                    baseColor: base,
                    controller: _controller,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.widthFactor,
    required this.height,
    required this.baseColor,
    required this.controller,
    this.radius = 10,
  });

  final double widthFactor;
  final double height;
  final double radius;
  final Color baseColor;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final shimmerWidth = width * 0.36;
              return AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final shift = (width + shimmerWidth) * controller.value;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: baseColor),
                      Transform.translate(
                        offset: Offset(shift - shimmerWidth, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: shimmerWidth,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(alpha: 0.32),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Stepper components
// ============================================================

class _WizardTopBar extends StatelessWidget {
  const _WizardTopBar({
    required this.step,
    required this.completedSteps,
    required this.onStepSelected,
    required this.onReset,
  });
  final _WizardStep step;
  final Set<_WizardStep> completedSteps;
  final ValueChanged<_WizardStep> onStepSelected;
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
                      _StepConnector(
                        completed: completedSteps.contains(
                          _WizardStep.values[i - 1],
                        ),
                      ),
                    _StepCircle(
                      number: i + 1,
                      label: _WizardStep.values[i].label,
                      onTap: completedSteps.contains(_WizardStep.values[i])
                          ? () => onStepSelected(_WizardStep.values[i])
                          : null,
                      state: completedSteps.contains(_WizardStep.values[i])
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
            icon: const Icon(Icons.first_page_rounded),
            tooltip: 'Nuevo escaneo',
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _WizardSidebar extends StatelessWidget {
  const _WizardSidebar({
    required this.step,
    required this.completedSteps,
    required this.onStepSelected,
    required this.onReset,
  });
  final _WizardStep step;
  final Set<_WizardStep> completedSteps;
  final ValueChanged<_WizardStep> onStepSelected;
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
              Icon(
                Icons.menu_book_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
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
              onTap: completedSteps.contains(_WizardStep.values[i])
                  ? () => onStepSelected(_WizardStep.values[i])
                  : null,
              state: completedSteps.contains(_WizardStep.values[i])
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
            icon: const Icon(Icons.first_page_rounded, size: 16),
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
    required this.onTap,
  });
  final int number;
  final String label;
  final _StepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isActive = state == _StepState.active;
    final isCompleted = state == _StepState.completed;
    final filled = isActive || isCompleted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
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
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: theme.colorScheme.onPrimary,
                    )
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
      ),
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
    required this.onTap,
  });
  final int number;
  final String label;
  final _StepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isActive = state == _StepState.active;
    final isCompleted = state == _StepState.completed;
    final filled = isActive || isCompleted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
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
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: theme.colorScheme.onPrimary,
                    )
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
      ),
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
          Text('¿Cómo quieres comenzar?', style: theme.textTheme.headlineSmall),
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
            subtitle: 'Escribe directamente o pega desde el portapapeles.',
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
                child: Icon(
                  icon,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 24,
                ),
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
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
    required this.imageQuarterTurns,
    required this.cropRect,
    required this.processing,
    required this.ocrVisualState,
    required this.ocrFinished,
    required this.ocrErrorMessage,
    required this.reduceMotionEnabled,
    required this.history,
    required this.onPickFile,
    required this.onPickImage,
    required this.onContinueImage,
    required this.onRotateImage,
    required this.onCropImage,
    required this.onOpenCamera,
    required this.onContinueText,
    required this.onHistorySelect,
  });
  final _WizardSource source;
  final TextEditingController textController;
  final String? imagePath;
  final int imageQuarterTurns;
  final Rect cropRect;
  final bool processing;
  final _OcrVisualState ocrVisualState;
  final bool ocrFinished;
  final String? ocrErrorMessage;
  final bool reduceMotionEnabled;
  final List<CaptureRecord> history;
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final VoidCallback onContinueImage;
  final VoidCallback onRotateImage;
  final VoidCallback onCropImage;
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
        source: source,
        imagePath: imagePath,
        imageQuarterTurns: imageQuarterTurns,
        cropRect: cropRect,
        processing: processing,
        ocrVisualState: ocrVisualState,
        ocrFinished: ocrFinished,
        ocrErrorMessage: ocrErrorMessage,
        reduceMotionEnabled: reduceMotionEnabled,
        onPickImage: onPickImage,
        onContinue: onContinueImage,
        onRotate: onRotateImage,
        onCrop: onCropImage,
      ),
      _WizardSource.camera => _ImagePickerContent(
        source: source,
        imagePath: imagePath,
        imageQuarterTurns: imageQuarterTurns,
        cropRect: cropRect,
        processing: processing,
        ocrVisualState: ocrVisualState,
        ocrFinished: ocrFinished,
        ocrErrorMessage: ocrErrorMessage,
        reduceMotionEnabled: reduceMotionEnabled,
        onPickImage: onOpenCamera,
        onContinue: onContinueImage,
        onRotate: onRotateImage,
        onCrop: onCropImage,
      ),
      _WizardSource.history => _HistoryListContent(
        history: history,
        onSelect: onHistorySelect,
      ),
    };
  }
}

class _TextInputContent extends StatelessWidget {
  const _TextInputContent({required this.controller, required this.onContinue});
  final TextEditingController controller;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Escribe o pega el texto',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
                onPressed: controller.text.trim().isNotEmpty
                    ? onContinue
                    : null,
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
  const _FilePickerContent({
    required this.processing,
    required this.onPickFile,
  });
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
            Icon(
              Icons.description_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona un archivo .txt',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'El contenido se cargará automáticamente.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
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
    required this.source,
    required this.imagePath,
    required this.imageQuarterTurns,
    required this.cropRect,
    required this.processing,
    required this.ocrVisualState,
    required this.ocrFinished,
    required this.ocrErrorMessage,
    required this.reduceMotionEnabled,
    required this.onPickImage,
    required this.onContinue,
    required this.onRotate,
    required this.onCrop,
  });
  final _WizardSource source;
  final String? imagePath;
  final int imageQuarterTurns;
  final Rect cropRect;
  final bool processing;
  final _OcrVisualState ocrVisualState;
  final bool ocrFinished;
  final String? ocrErrorMessage;
  final bool reduceMotionEnabled;
  final VoidCallback onPickImage;
  final VoidCallback onContinue;
  final VoidCallback onRotate;
  final VoidCallback onCrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = imagePath != null && File(imagePath!).existsSync();
    final mutedStatusTextStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      fontSize: 12,
    );
    final isCameraSource = source == _WizardSource.camera;
    final showOverlay = hasImage && ocrVisualState != _OcrVisualState.idle;
    final pickButtonLabel = isCameraSource
        ? (hasImage ? 'Tomar otra fotografía' : 'Tomar fotografía')
        : (hasImage ? 'Cambiar imagen' : 'Elegir imagen');
    final pickButtonIcon = isCameraSource
        ? Icons.camera_alt_outlined
        : hasImage
        ? Icons.refresh_outlined
        : Icons.photo_library_outlined;

    OcrOverlayState mapOverlayState() {
      return switch (ocrVisualState) {
        _OcrVisualState.failed => OcrOverlayState.failed,
        _OcrVisualState.completed ||
        _OcrVisualState.exiting => OcrOverlayState.completed,
        _ => OcrOverlayState.scanning,
      };
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isCameraSource ? 'Tomar fotografía' : 'Selecciona una imagen',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          if (hasImage)
            Container(
              key: const ValueKey('selected-image-preview'),
              height: 360,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: _ImageViewportOverlay(
                imagePath: imagePath!,
                imageQuarterTurns: imageQuarterTurns,
                cropRect: cropRect,
                showOverlay: showOverlay,
                exiting: ocrVisualState == _OcrVisualState.exiting,
                processing: processing,
                overlayState: mapOverlayState(),
                ocrErrorMessage: ocrErrorMessage,
                reduceMotionEnabled: reduceMotionEnabled,
              ),
            )
          else
            InkWell(
              key: const ValueKey('empty-image-picker'),
              onTap: processing ? null : onPickImage,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isCameraSource
                          ? Icons.camera_alt_outlined
                          : Icons.image_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isCameraSource ? 'Sin fotografía' : 'Sin imagen',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
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
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(pickButtonIcon),
            label: Text(processing ? 'Analizando…' : pickButtonLabel),
          ),
          if (hasImage && !processing) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onRotate,
                  icon: const Icon(Icons.rotate_right_outlined, size: 18),
                  label: const Text('Rotar'),
                ),
                OutlinedButton.icon(
                  onPressed: onCrop,
                  icon: const Icon(Icons.crop_outlined, size: 18),
                  label: const Text('Recortar'),
                ),
              ],
            ),
          ],
          if (processing && hasImage) ...[
            const SizedBox(height: 12),
            Text('Escaneando imagen con OCR...', style: mutedStatusTextStyle),
          ] else if (hasImage) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('continue-selected-image'),
              onPressed: onContinue,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Continuar'),
            ),
          ],
          if (ocrVisualState == _OcrVisualState.failed && !processing) ...[
            const SizedBox(height: 10),
            Text(
              ocrErrorMessage ?? 'No fue posible reconocer el texto',
              style: mutedStatusTextStyle,
            ),
          ],
          if (ocrFinished && !processing) ...[
            const SizedBox(height: 10),
            Text('Texto identificado ✓', style: mutedStatusTextStyle),
          ],
        ],
      ),
    );
  }
}

class _ImageViewportOverlay extends StatefulWidget {
  const _ImageViewportOverlay({
    required this.imagePath,
    required this.imageQuarterTurns,
    required this.cropRect,
    required this.showOverlay,
    required this.exiting,
    required this.processing,
    required this.overlayState,
    required this.ocrErrorMessage,
    required this.reduceMotionEnabled,
  });

  final String imagePath;
  final int imageQuarterTurns;
  final Rect cropRect;
  final bool showOverlay;
  final bool exiting;
  final bool processing;
  final OcrOverlayState overlayState;
  final String? ocrErrorMessage;
  final bool reduceMotionEnabled;

  @override
  State<_ImageViewportOverlay> createState() => _ImageViewportOverlayState();
}

class _ImageViewportOverlayState extends State<_ImageViewportOverlay> {
  Size? _sourceImageSize;

  @override
  void initState() {
    super.initState();
    _loadSourceImageSize();
  }

  @override
  void didUpdateWidget(covariant _ImageViewportOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _sourceImageSize = null;
      _loadSourceImageSize();
    }
  }

  Future<void> _loadSourceImageSize() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (!mounted || decoded == null) return;
      setState(() {
        _sourceImageSize = Size(
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        );
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        final source = _sourceImageSize;

        if (source == null || viewportWidth <= 0 || viewportHeight <= 0) {
          return Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: RotatedBox(
                    quarterTurns: widget.imageQuarterTurns,
                    child: Image.file(
                      File(widget.imagePath),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              _CropOverlayMask(cropRect: widget.cropRect),
              if (widget.showOverlay)
                AnimatedOpacity(
                  duration: widget.reduceMotionEnabled
                      ? Duration.zero
                      : const Duration(milliseconds: 400),
                  opacity: widget.exiting ? 0 : 1,
                  child: OcrScanOverlay(
                    active: widget.processing,
                    state: widget.overlayState,
                    showHud: true,
                    errorMessage: widget.ocrErrorMessage,
                  ),
                ),
            ],
          );
        }

        final imageAspectRatio = source.width / source.height;
        final viewportAspectRatio = viewportWidth / viewportHeight;

        late final double surfaceWidth;
        late final double surfaceHeight;
        if (imageAspectRatio > viewportAspectRatio) {
          surfaceWidth = viewportWidth;
          surfaceHeight = viewportWidth / imageAspectRatio;
        } else {
          surfaceHeight = viewportHeight;
          surfaceWidth = viewportHeight * imageAspectRatio;
        }

        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: SizedBox(
            width: viewportWidth,
            height: viewportHeight,
            child: Center(
              child: SizedBox(
                key: const ValueKey('selected-image-surface'),
                width: surfaceWidth,
                height: surfaceHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RotatedBox(
                      quarterTurns: widget.imageQuarterTurns,
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.fill,
                      ),
                    ),
                    _CropOverlayMask(cropRect: widget.cropRect),
                    if (widget.showOverlay)
                      AnimatedOpacity(
                        duration: widget.reduceMotionEnabled
                            ? Duration.zero
                            : const Duration(milliseconds: 400),
                        opacity: widget.exiting ? 0 : 1,
                        child: OcrScanOverlay(
                          active: widget.processing,
                          state: widget.overlayState,
                          showHud: true,
                          errorMessage: widget.ocrErrorMessage,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CropOverlayMask extends StatelessWidget {
  const _CropOverlayMask({required this.cropRect});

  final Rect cropRect;

  @override
  Widget build(BuildContext context) {
    final safe = Rect.fromLTWH(
      cropRect.left.clamp(0.0, 1.0),
      cropRect.top.clamp(0.0, 1.0),
      cropRect.width.clamp(0.1, 1.0),
      cropRect.height.clamp(0.1, 1.0),
    );

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final left = width * safe.left;
          final top = height * safe.top;
          final rectW = width * safe.width;
          final rectH = height * safe.height;

          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                  ),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: rectW,
                height: rectH,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CropSelectionPreview extends StatelessWidget {
  const _CropSelectionPreview({
    required this.imagePath,
    required this.cropRect,
    required this.onChanged,
  });

  final String imagePath;
  final Rect cropRect;
  final ValueChanged<Rect> onChanged;

  @override
  Widget build(BuildContext context) {
    return _GestureCropEditor(
      imagePath: imagePath,
      cropRect: cropRect,
      onChanged: onChanged,
    );
  }
}

enum _CropDragTarget {
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

class _GestureCropEditor extends StatefulWidget {
  const _GestureCropEditor({
    required this.imagePath,
    required this.cropRect,
    required this.onChanged,
  });

  final String imagePath;
  final Rect cropRect;
  final ValueChanged<Rect> onChanged;

  @override
  State<_GestureCropEditor> createState() => _GestureCropEditorState();
}

class _GestureCropEditorState extends State<_GestureCropEditor> {
  Size? _sourceSize;
  _CropDragTarget? _dragTarget;

  @override
  void initState() {
    super.initState();
    _loadSourceSize();
  }

  @override
  void didUpdateWidget(covariant _GestureCropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _sourceSize = null;
      _loadSourceSize();
    }
  }

  Future<void> _loadSourceSize() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (!mounted) return;
      if (decoded == null) {
        // Some formats/metadata may not decode here; keep editor usable.
        setState(() => _sourceSize = const Size(4, 3));
        return;
      }
      setState(() {
        _sourceSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      });
    } catch (_) {
      if (!mounted) return;
      // Fallback ratio keeps the crop editor usable when metadata cannot be read.
      setState(() => _sourceSize = const Size(4, 3));
    }
  }

  Rect _normalize(Rect value) {
    const minSize = 0.12;
    final width = value.width.clamp(minSize, 1.0);
    final height = value.height.clamp(minSize, 1.0);
    final left = value.left.clamp(0.0, 1.0 - width);
    final top = value.top.clamp(0.0, 1.0 - height);
    return Rect.fromLTWH(left, top, width, height);
  }

  _CropDragTarget? _resolveTarget(Offset localPosition, Size size) {
    final safe = _normalize(widget.cropRect);
    final left = safe.left * size.width;
    final top = safe.top * size.height;
    final right = (safe.left + safe.width) * size.width;
    final bottom = (safe.top + safe.height) * size.height;
    final centerX = (left + right) / 2;
    final centerY = (top + bottom) / 2;
    const handleRadius = 30.0;
    const edgeHitThickness = 22.0;
    final edgeHalfWidth = max(30.0, (right - left) * 0.2);
    final edgeHalfHeight = max(30.0, (bottom - top) * 0.2);

    bool near(Offset anchor) =>
        (localPosition - anchor).distance <= handleRadius;

    if (near(Offset(left, top))) return _CropDragTarget.topLeft;
    if (near(Offset(right, top))) return _CropDragTarget.topRight;
    if (near(Offset(left, bottom))) return _CropDragTarget.bottomLeft;
    if (near(Offset(right, bottom))) return _CropDragTarget.bottomRight;

    final nearTopSelector =
        (localPosition.dx - centerX).abs() <= edgeHalfWidth &&
        (localPosition.dy - top).abs() <= edgeHitThickness;
    if (nearTopSelector) return _CropDragTarget.top;

    final nearBottomSelector =
        (localPosition.dx - centerX).abs() <= edgeHalfWidth &&
        (localPosition.dy - bottom).abs() <= edgeHitThickness;
    if (nearBottomSelector) return _CropDragTarget.bottom;

    final nearLeftSelector =
        (localPosition.dx - left).abs() <= edgeHitThickness &&
        (localPosition.dy - centerY).abs() <= edgeHalfHeight;
    if (nearLeftSelector) return _CropDragTarget.left;

    final nearRightSelector =
        (localPosition.dx - right).abs() <= edgeHitThickness &&
        (localPosition.dy - centerY).abs() <= edgeHalfHeight;
    if (nearRightSelector) return _CropDragTarget.right;

    final inside =
        localPosition.dx >= left &&
        localPosition.dx <= right &&
        localPosition.dy >= top &&
        localPosition.dy <= bottom;
    if (inside) return _CropDragTarget.move;
    return null;
  }

  Rect _applyDelta(
    Rect current,
    Offset delta,
    Size size,
    _CropDragTarget target,
  ) {
    const minSize = 0.12;
    final ndx = delta.dx / size.width;
    final ndy = delta.dy / size.height;

    double left = current.left;
    double top = current.top;
    double right = current.right;
    double bottom = current.bottom;

    switch (target) {
      case _CropDragTarget.move:
        final width = current.width;
        final height = current.height;
        left = (left + ndx).clamp(0.0, 1.0 - width);
        top = (top + ndy).clamp(0.0, 1.0 - height);
        right = left + width;
        bottom = top + height;
      case _CropDragTarget.topLeft:
        left = (left + ndx).clamp(0.0, right - minSize);
        top = (top + ndy).clamp(0.0, bottom - minSize);
      case _CropDragTarget.topRight:
        right = (right + ndx).clamp(left + minSize, 1.0);
        top = (top + ndy).clamp(0.0, bottom - minSize);
      case _CropDragTarget.bottomLeft:
        left = (left + ndx).clamp(0.0, right - minSize);
        bottom = (bottom + ndy).clamp(top + minSize, 1.0);
      case _CropDragTarget.bottomRight:
        right = (right + ndx).clamp(left + minSize, 1.0);
        bottom = (bottom + ndy).clamp(top + minSize, 1.0);
      case _CropDragTarget.top:
        top = (top + ndy).clamp(0.0, bottom - minSize);
      case _CropDragTarget.bottom:
        bottom = (bottom + ndy).clamp(top + minSize, 1.0);
      case _CropDragTarget.left:
        left = (left + ndx).clamp(0.0, right - minSize);
      case _CropDragTarget.right:
        right = (right + ndx).clamp(left + minSize, 1.0);
    }

    return _normalize(Rect.fromLTRB(left, top, right, bottom));
  }

  @override
  Widget build(BuildContext context) {
    final imageSize = _sourceSize;
    if (imageSize == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: AspectRatio(
          aspectRatio: imageSize.width / imageSize.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) {
                  setState(() {
                    _dragTarget = _resolveTarget(details.localPosition, size);
                  });
                },
                onPanUpdate: (details) {
                  final target = _dragTarget;
                  if (target == null) return;
                  final next = _applyDelta(
                    widget.cropRect,
                    details.delta,
                    size,
                    target,
                  );
                  widget.onChanged(next);
                },
                onPanEnd: (_) => setState(() => _dragTarget = null),
                onPanCancel: () => setState(() => _dragTarget = null),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(widget.imagePath), fit: BoxFit.fill),
                    _CropOverlayMask(cropRect: widget.cropRect),
                    _CropHandlesOverlay(cropRect: widget.cropRect),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CropHandlesOverlay extends StatelessWidget {
  const _CropHandlesOverlay({required this.cropRect});

  final Rect cropRect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safe = Rect.fromLTWH(
      cropRect.left.clamp(0.0, 1.0),
      cropRect.top.clamp(0.0, 1.0),
      cropRect.width.clamp(0.12, 1.0),
      cropRect.height.clamp(0.12, 1.0),
    );

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final left = width * safe.left;
          final top = height * safe.top;
          final right = width * (safe.left + safe.width);
          final bottom = height * (safe.top + safe.height);
          final centerX = (left + right) / 2;
          final centerY = (top + bottom) / 2;
          final selectorColor = Colors.orange.shade200;
          final selectorBorderColor = Colors.orange.shade600;

          Widget cornerHandle(double x, double y) {
            return Positioned(
              left: x - 12,
              top: y - 12,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            );
          }

          Widget horizontalSelector(double x, double y) {
            return Positioned(
              left: x - 28,
              top: y - 8,
              child: Container(
                width: 56,
                height: 16,
                decoration: BoxDecoration(
                  color: selectorColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selectorBorderColor, width: 1.6),
                ),
              ),
            );
          }

          Widget verticalSelector(double x, double y) {
            return Positioned(
              left: x - 8,
              top: y - 28,
              child: Container(
                width: 16,
                height: 56,
                decoration: BoxDecoration(
                  color: selectorColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selectorBorderColor, width: 1.6),
                ),
              ),
            );
          }

          return Stack(
            children: [
              cornerHandle(left, top),
              cornerHandle(right, top),
              cornerHandle(left, bottom),
              cornerHandle(right, bottom),
              horizontalSelector(centerX, top),
              horizontalSelector(centerX, bottom),
              verticalSelector(left, centerY),
              verticalSelector(right, centerY),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryListContent extends StatelessWidget {
  const _HistoryListContent({required this.history, required this.onSelect});
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
              Icon(
                Icons.history_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('Sin historial', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Tus escaneos guardados aparecerán aquí.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
                      Icon(
                        Icons.history_rounded,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTimestamp(record.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
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
    required this.detectingReferences,
    required this.detectionVisualState,
    required this.reduceMotionEnabled,
    required this.onBack,
    required this.onContinue,
  });
  final TextEditingController textController;
  final bool detectingReferences;
  final _OcrVisualState detectionVisualState;
  final bool reduceMotionEnabled;
  final VoidCallback onBack;
  final Future<void> Function() onContinue;

  @override
  State<_ReviewTextStep> createState() => _ReviewTextStepState();
}

class _ReviewTextStepState extends State<_ReviewTextStep> {
  bool _showPreview = true;
  bool _showEditingHelp = false;
  List<VerseMatch> _previewMatches = const [];
  int _activePreviewMatchIndex = 0;
  final ScrollController _previewScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _refreshPreview();
  }

  void _refreshPreview() {
    final text = widget.textController.text;
    setState(() {
      _previewMatches = extractVerseMatches(text);
      _showPreview = true;
      _activePreviewMatchIndex = 0;
    });
  }

  @override
  void dispose() {
    _previewScrollController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    if (_showPreview) {
      setState(() => _showPreview = false);
      return;
    }
    _refreshPreview();
  }

  void _navigatePreviewMatch(int delta) {
    if (_previewMatches.isEmpty) return;
    final next = (_activePreviewMatchIndex + delta).clamp(
      0,
      _previewMatches.length - 1,
    );
    if (next == _activePreviewMatchIndex) return;
    setState(() => _activePreviewMatchIndex = next);

    if (!_previewScrollController.hasClients) return;
    final text = widget.textController.text;
    if (text.isEmpty) return;
    final match = _previewMatches[next];
    final ratio = (match.start / text.length).clamp(0.0, 1.0);
    final target = _previewScrollController.position.maxScrollExtent * ratio;
    if (widget.reduceMotionEnabled) {
      _previewScrollController.jumpTo(target);
      return;
    }
    _previewScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  TextSpan _buildHighlightedPreview(String text, ThemeData theme) {
    final spans = <InlineSpan>[];
    final sorted = [..._previewMatches]
      ..sort((a, b) => a.start.compareTo(b.start));
    var pos = 0;
    final activeIndex = _activePreviewMatchIndex.clamp(
      0,
      sorted.isEmpty ? 0 : sorted.length - 1,
    );

    for (var index = 0; index < sorted.length; index++) {
      final match = sorted[index];
      final start = match.start.clamp(0, text.length);
      final end = match.end.clamp(0, text.length);
      if (start >= end) continue;
      if (start > pos) {
        spans.add(TextSpan(text: text.substring(pos, start)));
      }

      final isActive = index == activeIndex;
      final activeTextColor = theme.colorScheme.onPrimaryContainer;
      final activeBackground = theme.colorScheme.primaryContainer;
      final defaultTextColor = const Color(0xFFAD1457);
      final defaultBackground = const Color(0xFFF8BBD0);

      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(
            color: isActive ? activeTextColor : defaultTextColor,
            fontWeight: FontWeight.bold,
            backgroundColor: isActive ? activeBackground : defaultBackground,
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
    final keyboardVisible = View.of(context).viewInsets.bottom > 0;
    final compactMode = keyboardVisible;
    final isBusy = widget.detectingReferences;
    final charCount = widget.textController.text.length;
    final previewText = widget.textController.text;
    final previewLabel = _previewMatches.length == 1
        ? '1 cita resaltada'
        : '${_previewMatches.length} citas resaltadas';

    OcrOverlayState mapOverlayState() {
      return switch (widget.detectionVisualState) {
        _OcrVisualState.completed ||
        _OcrVisualState.exiting => OcrOverlayState.completed,
        _ => OcrOverlayState.scanning,
      };
    }

    return SizedBox.expand(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: keyboardVisible ? 8 : 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Revisar el texto reconocido',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Edita cualquier parte si es necesario.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                compactMode
                    ? IconButton.outlined(
                        key: const ValueKey('review-mode-toggle'),
                        onPressed: (previewText.trim().isEmpty || isBusy)
                            ? null
                            : _toggleMode,
                        icon: Icon(
                          _showPreview
                              ? Icons.edit_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        tooltip: _showPreview ? 'Editar' : 'Vista previa',
                      )
                    : OutlinedButton.icon(
                        key: const ValueKey('review-mode-toggle'),
                        onPressed: (previewText.trim().isEmpty || isBusy)
                            ? null
                            : _toggleMode,
                        icon: Icon(
                          _showPreview
                              ? Icons.edit_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        label: Text(_showPreview ? 'Editar' : 'Vista previa'),
                      ),
              ],
            ),
            const SizedBox(height: kWizardPanelSpacing),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _previewMatches.isEmpty
                                          ? 'Sin citas detectadas'
                                          : 'Cita ${_activePreviewMatchIndex + 1} de ${_previewMatches.length}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Cita anterior',
                                    onPressed: _previewMatches.isEmpty
                                        ? null
                                        : () => _navigatePreviewMatch(-1),
                                    icon: const Icon(Icons.keyboard_arrow_up),
                                  ),
                                  IconButton(
                                    tooltip: 'Siguiente cita',
                                    onPressed: _previewMatches.isEmpty
                                        ? null
                                        : () => _navigatePreviewMatch(1),
                                    icon: const Icon(Icons.keyboard_arrow_down),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _previewScrollController,
                                  child: SelectableText.rich(
                                    _buildHighlightedPreview(
                                      previewText,
                                      theme,
                                    ),
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
                  final editorField = Column(
                    children: [
                      if (!compactMode) ...[
                        ExpansionTile(
                          initiallyExpanded: _showEditingHelp,
                          onExpansionChanged: (expanded) {
                            setState(() => _showEditingHelp = expanded);
                          },
                          title: const Text('Ayuda de formato de citas'),
                          subtitle: const Text(
                            'Ejemplos válidos para detección',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          children: const [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Ejemplos: Juan 3:16, Salmos 23:1-4, 1 Corintios 13:4',
                              ),
                            ),
                            SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('También: Mateo 5:3, 5:4, 5:9'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(
                        child: TextField(
                          key: const ValueKey('review-text-field'),
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
                      ),
                    ],
                  );

                  return SizedBox.expand(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _showPreview ? previewPanel : editorField,
                        if (widget.detectionVisualState != _OcrVisualState.idle)
                          AnimatedOpacity(
                            duration: widget.reduceMotionEnabled
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            opacity:
                                widget.detectionVisualState ==
                                    _OcrVisualState.exiting
                                ? 0
                                : 1,
                            child: OcrScanOverlay(
                              active: widget.detectingReferences,
                              state: mapOverlayState(),
                              showHud: true,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (keyboardVisible)
              Row(
                children: [
                  Expanded(
                    key: const ValueKey('review-summary'),
                    child: Text(
                      '$charCount car. · '
                      '${_showPreview ? _previewMatches.length : 0} citas',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: isBusy ? null : widget.onBack,
                    child: const Text('Atrás'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: charCount > 0 && !isBusy
                        ? () => widget.onContinue()
                        : null,
                    child: const Text('Continuar'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    key: const ValueKey('review-summary'),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          '$charCount caracteres',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          previewText.trim().isEmpty || !_showPreview
                              ? '0 citas resaltadas'
                              : previewLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: isBusy ? null : widget.onBack,
                    child: const Text('Atrás'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: charCount > 0 && !isBusy
                        ? () => widget.onContinue()
                        : null,
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
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: groupedRefs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Sin citas bíblicas detectadas.',
                          style: theme.textTheme.bodyMedium,
                        ),
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
                                  child: _RefCountList(refs: groupedRefs),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: _AnalysisSummaryCard(
                                    charCount: charCount,
                                    refCount: groupedRefs.length,
                                    duration: detectionDuration!,
                                  ),
                                ),
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
                                  child: _RefCountList(refs: groupedRefs),
                                ),
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
            Text('Resumen del análisis', style: theme.textTheme.titleSmall),
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
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });
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
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
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
    required this.compactView,
    required this.reduceMotionEnabled,
    required this.onRefSelected,
    required this.onNavigate,
    required this.onToggleCompactView,
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
  final bool compactView;
  final bool reduceMotionEnabled;
  final void Function(String, int) onRefSelected;
  final ValueChanged<int> onNavigate;
  final ValueChanged<bool> onToggleCompactView;
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
          const SizedBox(height: 12),
          Row(
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Tarjeta'),
                    icon: Icon(Icons.style_outlined),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Lista'),
                    icon: Icon(Icons.view_list_outlined),
                  ),
                ],
                selected: <bool>{compactView},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  onToggleCompactView(selection.first);
                },
              ),
              const Spacer(),
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
          const SizedBox(height: 8),
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
                          showPositionPrefix: false,
                          onSelect: onRefSelected,
                        ),
                      ),
                      const VerticalDivider(width: 16),
                      Expanded(
                        child: _VersePanel(
                          activeReference: activeReference,
                          bibleText: bibleText,
                          bibleMessage: bibleMessage,
                          loading: loadingBibleText,
                          copiedFeedbackVisible: copiedFeedbackVisible,
                          onCopyBibleText: onCopyBibleText,
                        ),
                      ),
                    ],
                  )
                : compactView
                ? Column(
                    children: [
                      SizedBox(
                        height: 150,
                        child: _RefListPanel(
                          refs: groupedRefs,
                          currentIndex: currentRefIndex,
                          showPositionPrefix: true,
                          onSelect: onRefSelected,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _VersePanel(
                          activeReference: activeReference,
                          bibleText: bibleText,
                          bibleMessage: bibleMessage,
                          loading: loadingBibleText,
                          copiedFeedbackVisible: copiedFeedbackVisible,
                          onCopyBibleText: onCopyBibleText,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _VersePanel(
                          activeReference: activeReference,
                          bibleText: bibleText,
                          bibleMessage: bibleMessage,
                          loading: loadingBibleText,
                          copiedFeedbackVisible: copiedFeedbackVisible,
                          onCopyBibleText: onCopyBibleText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 56,
                        child: _RefChipsPanel(
                          refs: groupedRefs,
                          currentIndex: currentRefIndex,
                          reduceMotionEnabled: reduceMotionEnabled,
                          onSelect: onRefSelected,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          if (isDesktop)
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
            )
          else
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: currentRefIndex > 0
                          ? () => onNavigate(-1)
                          : null,
                    ),
                    SizedBox(
                      width: 112,
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
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onBack,
                        child: const Text('Atrás'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onContinue,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Finalizar'),
                      ),
                    ),
                  ],
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
    required this.showPositionPrefix,
    required this.onSelect,
  });
  final List<({String reference, int count})> refs;
  final int currentIndex;
  final bool showPositionPrefix;
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
          selectedTileColor: theme.colorScheme.primaryContainer.withValues(
            alpha: 0.3,
          ),
          title: Text(
            showPositionPrefix
                ? '(${i + 1} de ${refs.length}) ${ref.reference}'
                : ref.reference,
            style: theme.textTheme.bodySmall,
          ),
          onTap: () => onSelect(ref.reference, i),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
      },
    );
  }
}

class _RefChipsPanel extends StatefulWidget {
  const _RefChipsPanel({
    required this.refs,
    required this.currentIndex,
    required this.reduceMotionEnabled,
    required this.onSelect,
  });
  final List<({String reference, int count})> refs;
  final int currentIndex;
  final bool reduceMotionEnabled;
  final void Function(String, int) onSelect;

  @override
  State<_RefChipsPanel> createState() => _RefChipsPanelState();
}

class _RefChipsPanelState extends State<_RefChipsPanel> {
  late final ScrollController _scrollController;
  final List<GlobalKey> _chipKeys = <GlobalKey>[];

  void _syncChipKeys() {
    final missing = widget.refs.length - _chipKeys.length;
    if (missing > 0) {
      for (var i = 0; i < missing; i++) {
        _chipKeys.add(GlobalKey());
      }
    } else if (missing < 0) {
      _chipKeys.removeRange(widget.refs.length, _chipKeys.length);
    }
  }

  @override
  void initState() {
    super.initState();
    _syncChipKeys();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveChip());
  }

  @override
  void didUpdateWidget(covariant _RefChipsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncChipKeys();
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.refs.length != widget.refs.length) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToActiveChip(),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveChip() {
    if (!_scrollController.hasClients || widget.refs.isEmpty) return;
    final index = widget.currentIndex.clamp(0, widget.refs.length - 1);
    final chipContext = _chipKeys[index].currentContext;
    if (chipContext == null) return;
    final scrollContext =
        _scrollController.position.context.notificationContext;
    if (scrollContext == null) return;

    final chipBox = chipContext.findRenderObject() as RenderBox?;
    final viewportBox = scrollContext.findRenderObject() as RenderBox?;
    if (chipBox == null || viewportBox == null) return;

    final chipOffset = chipBox
        .localToGlobal(Offset.zero, ancestor: viewportBox)
        .dx;
    final chipWidth = chipBox.size.width;
    const edgePadding = 8.0;
    final viewportWidth = viewportBox.size.width;

    final currentOffset = _scrollController.offset;
    final minVisibleX = edgePadding;
    final maxVisibleX = viewportWidth - edgePadding;

    double targetOffset = currentOffset;
    if (chipOffset < minVisibleX) {
      targetOffset = currentOffset - (minVisibleX - chipOffset);
    } else if (chipOffset + chipWidth > maxVisibleX) {
      targetOffset = currentOffset + ((chipOffset + chipWidth) - maxVisibleX);
    }

    final clamped = targetOffset.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    if ((clamped - currentOffset).abs() < 0.5) return;
    if (widget.reduceMotionEnabled) {
      _scrollController.jumpTo(clamped.toDouble());
      return;
    }
    _scrollController.animateTo(
      clamped.toDouble(),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: widget.refs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final ref = widget.refs[i];
        final isActive = i == widget.currentIndex;
        return KeyedSubtree(
          key: _chipKeys[i],
          child: FilterChip(
            selected: isActive,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text(ref.reference),
            selectedColor: theme.colorScheme.primaryContainer,
            checkmarkColor: theme.colorScheme.onPrimaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: BorderSide(
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: isActive ? 1.6 : 1,
            ),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: isActive
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
            onSelected: (_) => widget.onSelect(ref.reference, i),
          ),
        );
      },
    );
  }
}

class _VersePanel extends StatelessWidget {
  const _VersePanel({
    required this.activeReference,
    required this.bibleText,
    required this.bibleMessage,
    required this.loading,
    required this.copiedFeedbackVisible,
    required this.onCopyBibleText,
  });
  final String? activeReference;
  final String? bibleText;
  final String bibleMessage;
  final bool loading;
  final bool copiedFeedbackVisible;
  final VoidCallback onCopyBibleText;

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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outline, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 14,
            spreadRadius: 1,
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  activeReference == null
                      ? bibleMessage
                      : '${activeReference!}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: bibleText != null ? onCopyBibleText : null,
                tooltip: 'Copiar texto',
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
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: text != null
                  ? Text(
                      '"$text"',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                        fontSize: 18,
                        fontFamily: 'Times New Roman',
                        fontFamilyFallback: const [
                          'Times',
                          'Noto Serif',
                          'serif',
                        ],
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
          ),
        ],
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
    required this.reduceMotionEnabled,
    required this.recentExports,
    required this.exportDirectoryPath,
    required this.onSaveToHistory,
    required this.onCopyReferences,
    required this.onShareResult,
    required this.onExportText,
    required this.onToggleIncludeBibleText,
    required this.onToggleReduceMotion,
    required this.onRetryExport,
    required this.onNewScan,
  });
  final int refCount;
  final bool savedToHistory;
  final _FinishAction completedAction;
  final bool includeBibleTextInOutput;
  final bool reduceMotionEnabled;
  final List<ExportHistoryItem> recentExports;
  final String? exportDirectoryPath;
  final VoidCallback onSaveToHistory;
  final VoidCallback onCopyReferences;
  final VoidCallback onShareResult;
  final VoidCallback onExportText;
  final ValueChanged<bool> onToggleIncludeBibleText;
  final ValueChanged<bool> onToggleReduceMotion;
  final ValueChanged<ExportHistoryItem> onRetryExport;
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
            child: Icon(
              Icons.check_circle_rounded,
              color: Colors.green.shade700,
              size: 52,
            ),
          ),
          const SizedBox(height: 20),
          Text('¡Escaneo completado!', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Se encontraron $refCount citas bíblicas.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: includeBibleTextInOutput,
            onChanged: onToggleIncludeBibleText,
            title: const Text('Incluir texto bíblico en resultados'),
            subtitle: const Text(
              'Se añadirá el texto bíblico de cada cita cuando sea posible.',
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: reduceMotionEnabled,
            onChanged: onToggleReduceMotion,
            title: const Text('Reducir animaciones'),
            subtitle: const Text(
              'Desactiva transiciones no críticas para mejorar accesibilidad visual.',
            ),
          ),
          if (exportDirectoryPath != null &&
              exportDirectoryPath!.isNotEmpty) ...[
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
            subtitle:
                'Copia solo las citas bíblicas encontradas y su texto bíblico si está activado.',
            onTap: onCopyReferences,
            trailing: completedAction == _FinishAction.copiedCitations
                ? Icon(Icons.check_circle, color: Colors.green.shade600)
                : null,
          ),
          const SizedBox(height: 12),
          _FinishCard(
            icon: Icons.share_outlined,
            title: 'Copiar resultado escaneado',
            subtitle:
                'Copia solo el texto escaneado y su texto bíblico si está activado.',
            onTap: onShareResult,
            trailing: completedAction == _FinishAction.copiedScannedResult
                ? Icon(Icons.check_circle, color: Colors.green.shade600)
                : null,
          ),
          if (kEnableTextExport) ...[
            const SizedBox(height: 12),
            _FinishCard(
              icon: Icons.download_outlined,
              title: 'Exportar texto',
              subtitle:
                  'Exporta el texto escaneado con citas y texto bíblico opcional en un archivo .txt.',
              onTap: onExportText,
              trailing: completedAction == _FinishAction.exported
                  ? Icon(Icons.check_circle, color: Colors.green.shade600)
                  : null,
            ),
          ],
          if (recentExports.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Últimas exportaciones',
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            for (final item in recentExports) ...[
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.history_outlined),
                  title: Text(
                    p.basename(item.filePath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatTimestamp(item.timestamp)} · ${item.format.toUpperCase()}\n${item.filePath}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Reintentar exportación',
                    icon: const Icon(Icons.replay_outlined),
                    onPressed: () => onRetryExport(item),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNewScan,
              icon: const Icon(Icons.first_page_rounded),
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
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
