part of '../main.dart';

enum InputSource { text, image, camera }

typedef BibleTextLookup =
    Future<String?> Function(String reference, int bibleVersionId);
typedef ImageFilePicker = Future<String?> Function();
typedef OcrTextRecognizer = Future<String> Function(String imagePath);

const bool kEnableHistoryFeature = false;
const bool kEnableTextExport = false;
const bool kShowBanner = false;
const String kAppTitle = 'Verse Catch';
const String kAppVersionLabel = 'v1.0';
const String kNoBibleTextMessage =
    'Select a highlighted biblical citation to view biblical text.';
const String kLoadingBibleTextMessage = 'Loading biblical text...';
const String kIncludeBibleTextSettingKey = 'include_bible_text_in_output';
const String kExportDirectorySettingKey = 'export_directory_path';
const String kReduceMotionSettingKey = 'reduce_motion_enabled';
const String kExportHistorySettingKey = 'export_history_json';
const double kWizardSectionSpacing = 16;
const double kWizardPanelSpacing = 12;
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

Future<String?> pickImageFileFromDevice() async {
  final result = await FilePicker.pickFiles(type: FileType.image);
  return result?.files.single.path;
}

void _validateMasterBookAliasesOrThrow() {
  final ownerByAlias = <String, String>{};
  final sourceByAlias = <String, String>{};
  final collisions = <String>[];

  for (final entry in _kMasterBookKeys.entries) {
    final usfmBook = entry.key;
    for (final alias in entry.value.aliases) {
      final normalizedAlias = _normalizeBookAlias(alias);
      final existingOwner = ownerByAlias[normalizedAlias];
      if (existingOwner == null) {
        ownerByAlias[normalizedAlias] = usfmBook;
        sourceByAlias[normalizedAlias] = alias;
        continue;
      }
      if (existingOwner == usfmBook) continue;

      final firstAlias = sourceByAlias[normalizedAlias] ?? normalizedAlias;
      collisions.add(
        'Alias "$firstAlias" (normalized: "$normalizedAlias") is assigned to both '
        '$existingOwner and $usfmBook.',
      );
    }
  }

  if (collisions.isNotEmpty) {
    throw StateError(
      'Duplicate book aliases detected in _kMasterBookKeys:\n${collisions.join('\n')}',
    );
  }
}

void _validateMasterBookChapterMetadataOrThrow() {
  final missingChapterCounts = _kMasterBookKeys.keys
      .where((usfmBook) => !_kChapterCountByUsfmBook.containsKey(usfmBook))
      .toList();
  if (missingChapterCounts.isNotEmpty) {
    throw StateError(
      'Missing chapter count metadata in _kChapterCountByUsfmBook for: '
      '${missingChapterCounts.join(', ')}',
    );
  }

  final unknownChapterCountBooks = _kChapterCountByUsfmBook.keys
      .where((usfmBook) => !_kMasterBookKeys.containsKey(usfmBook))
      .toList();
  if (unknownChapterCountBooks.isNotEmpty) {
    throw StateError(
      'Unknown USFM keys found in _kChapterCountByUsfmBook: '
      '${unknownChapterCountBooks.join(', ')}',
    );
  }
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
    this.imageFilePicker = pickImageFileFromDevice,
    this.ocrTextRecognizer,
  });

  final BibleTextLookup bibleTextLookup;
  final ImageFilePicker imageFilePicker;
  final OcrTextRecognizer? ocrTextRecognizer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '$kAppTitle $kAppVersionLabel',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            disabledBackgroundColor: colorScheme.onSurface.withValues(
              alpha: 0.18,
            ),
            disabledForegroundColor: colorScheme.onSurface.withValues(
              alpha: 0.62,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colorScheme.outline),
            disabledForegroundColor: colorScheme.onSurface.withValues(
              alpha: 0.52,
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            disabledForegroundColor: colorScheme.onSurface.withValues(
              alpha: 0.52,
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          side: BorderSide(color: colorScheme.outline),
          selectedColor: colorScheme.primaryContainer,
          disabledColor: colorScheme.surfaceContainerHighest,
          labelStyle: TextStyle(color: colorScheme.onSurface),
          secondaryLabelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      home: WizardHomePage(
        bibleTextLookup: bibleTextLookup,
        imageFilePicker: imageFilePicker,
        ocrTextRecognizer: ocrTextRecognizer,
      ),
    );
  }
}
