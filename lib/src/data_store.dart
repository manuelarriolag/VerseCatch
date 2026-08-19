part of '../main.dart';

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

class ExportHistoryItem {
  const ExportHistoryItem({
    required this.timestamp,
    required this.format,
    required this.filePath,
  });

  final DateTime timestamp;
  final String format;
  final String filePath;

  Map<String, Object?> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'format': format,
      'file_path': filePath,
    };
  }

  factory ExportHistoryItem.fromMap(Map<String, Object?> map) {
    return ExportHistoryItem(
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      format: map['format'] as String? ?? 'txt',
      filePath: map['file_path'] as String? ?? '',
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

  Future<bool> reduceMotionEnabled() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_kReduceMotionSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return (rows.first['value'] as String?) == 'true';
  }

  Future<void> setReduceMotionEnabled(bool value) async {
    final db = await _db;
    await db.insert('app_settings', <String, Object?>{
      'key': _kReduceMotionSettingKey,
      'value': value ? 'true' : 'false',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ExportHistoryItem>> recentExports({int limit = 5}) async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_kExportHistorySettingKey],
      limit: 1,
    );
    if (rows.isEmpty) return const [];
    final json = rows.first['value'] as String?;
    if (json == null || json.isEmpty) return const [];
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    final parsed = decoded
        .whereType<Map>()
        .map(
          (item) => ExportHistoryItem.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((item) => item.filePath.trim().isNotEmpty)
        .toList(growable: false);
    if (parsed.length <= limit) return parsed;
    return parsed.take(limit).toList(growable: false);
  }

  Future<void> pushExportHistory(
    ExportHistoryItem item, {
    int limit = 5,
  }) async {
    final current = await recentExports(limit: limit);
    final deduped = <ExportHistoryItem>[item];
    for (final existing in current) {
      if (existing.filePath == item.filePath &&
          existing.format == item.format) {
        continue;
      }
      deduped.add(existing);
      if (deduped.length >= limit) break;
    }
    final db = await _db;
    await db.insert('app_settings', <String, Object?>{
      'key': _kExportHistorySettingKey,
      'value': jsonEncode(deduped.map((entry) => entry.toMap()).toList()),
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
const String _kReduceMotionSettingKey = 'reduce_motion_enabled';
const String _kExportHistorySettingKey = 'export_history_json';
