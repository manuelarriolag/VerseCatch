part of '../main.dart';

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

    final usfmBookCode = _resolveUsfmBookCode(book);
    if (usfmBookCode == null) {
      continue;
    }
    if (!_isValidChapterForUsfmBook(usfmBookCode: usfmBookCode, chapter: chapter)) {
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
      if (
        _isValidChapterForUsfmBook(
          usfmBookCode: usfmBookCode,
          chapter: continuedChapter,
        )
      ) {
        references.add(
          '$book $continuedChapter:$continuedVerse${continuedVerseEnd == null ? '' : '-$continuedVerseEnd'}',
        );
      }
      cursor += continuation.end;
    }
  }

  for (final match in _kChapterOnlyPattern.allMatches(normalized)) {
    final book = match.group(1)!;
    final chapter = match.group(2)!;
    final usfmBookCode = _resolveUsfmBookCode(book);
    if (usfmBookCode == null) {
      continue;
    }
    if (
      !_isSingleChapterUsfmBook(usfmBookCode) &&
      !_isValidChapterForUsfmBook(usfmBookCode: usfmBookCode, chapter: chapter)
    ) {
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

  final usfmBook = _resolveUsfmBookCode(match.group(1)!);
  if (usfmBook == null) {
    throw YouVersionApiException(
      'Unsupported biblical book for remote lookup: ${match.group(1)}',
    );
  }
  var chapter = match.group(2)!;
  var verse = match.group(3);
  final verseEnd = match.group(4);
  if (verse == null &&
      _isSingleChapterUsfmBook(usfmBook) &&
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
  final lower = book.trim().toLowerCase();
  final ascii = lower
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
  return ascii.replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

bool _isKnownBiblicalBook(String book) {
  return _resolveUsfmBookCode(book) != null;
}

String _normalizeBookAlias(String book) {
  var normalized = _normalizeBookKey(book);
  normalized = normalized.replaceFirst(RegExp(r'^primer(?=[a-z])'), '1');
  normalized = normalized.replaceFirst(RegExp(r'^primero(?=[a-z])'), '1');
  normalized = normalized.replaceFirst(RegExp(r'^primera(?=[a-z])'), '1');
  normalized = normalized.replaceFirst(RegExp(r'^first(?=[a-z])'), '1');
  normalized = normalized.replaceFirst(RegExp(r'^segundo(?=[a-z])'), '2');
  normalized = normalized.replaceFirst(RegExp(r'^segunda(?=[a-z])'), '2');
  normalized = normalized.replaceFirst(RegExp(r'^second(?=[a-z])'), '2');
  normalized = normalized.replaceFirst(RegExp(r'^tercer(?=[a-z])'), '3');
  normalized = normalized.replaceFirst(RegExp(r'^tercero(?=[a-z])'), '3');
  normalized = normalized.replaceFirst(RegExp(r'^tercera(?=[a-z])'), '3');
  normalized = normalized.replaceFirst(RegExp(r'^third(?=[a-z])'), '3');
  // normalized = normalized.replaceFirst(RegExp(r'^iii(?=[a-z])'), '3');
  // normalized = normalized.replaceFirst(RegExp(r'^ii(?=[a-z])'), '2');
  // normalized = normalized.replaceFirst(RegExp(r'^i(?=[a-z])'), '1');
  return normalized;
}

final Map<String, String> _kUsfmBookCodeByAlias = () {
  final result = <String, String>{};
  for (final entry in _kMasterBookKeys.entries) {
    result[_normalizeBookAlias(entry.key)] = entry.key;
    for (final alias in entry.value.aliases) {
      result[_normalizeBookAlias(alias)] = entry.key;
    }
  }
  return result;
}();

String? _resolveUsfmBookCode(String book) {
  return _kUsfmBookCodeByAlias[_normalizeBookAlias(book)];
}

bool _isSingleChapterUsfmBook(String usfmBookCode) {
  final book = _kMasterBookKeys[usfmBookCode];
  return book?.singleChapter ?? false;
}

String _normalizeChapterOnlyReference({
  required String book,
  required String chapterOrVerse,
}) {
  final usfmBookCode = _resolveUsfmBookCode(book);
  if (usfmBookCode != null && _isSingleChapterUsfmBook(usfmBookCode)) {
    return '$book 1:$chapterOrVerse';
  }
  return '$book $chapterOrVerse';
}

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
