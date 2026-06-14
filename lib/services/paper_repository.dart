import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../models/paper.dart';

class PaperRepository {
  PaperRepository();

  Database? _db;
  String? _deviceId;
  String? _syncDirectory;
  Timer? _exportTimer;
  bool _syncing = false;

  String get deviceId => _deviceId ?? 'unknown';
  String get syncDirectory => _syncDirectory ?? '';

  Future<void> init() async {
    if (Platform.isWindows || Platform.isLinux) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }

    final docs = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(docs.path, 'Tackboard'));
    if (!dbDir.existsSync()) dbDir.createSync(recursive: true);

    _db = await openDatabase(
      p.join(dbDir.path, 'tackboard.sqlite'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE papers (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            json TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );

    _deviceId = await _setting('device_id');
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = _newDeviceId();
      await _setSetting('device_id', _deviceId!);
    }

    _syncDirectory = await _setting('sync_directory');
    if (_syncDirectory == null || _syncDirectory!.isEmpty) {
      final defaultSync = Directory(p.join(dbDir.path, 'sync'));
      if (!defaultSync.existsSync()) defaultSync.createSync(recursive: true);
      _syncDirectory = defaultSync.path;
      await _setSetting('sync_directory', _syncDirectory!);
    }

    await syncNow();
  }

  Future<List<Paper>> loadPapers() async {
    final db = _requireDb();
    final rows = await db.query(
      'papers',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at ASC',
    );
    final papers = <Paper>[];
    for (final row in rows) {
      try {
        papers.add(Paper.fromJsonString(row['json'] as String));
      } catch (_) {
        // Keep the app usable if one synced JSON row is malformed.
      }
    }
    papers.sort((a, b) {
      final byZ = a.z.compareTo(b.z);
      return byZ != 0 ? byZ : a.createdAt.compareTo(b.createdAt);
    });
    return papers;
  }

  Future<void> savePaper(Paper paper, {bool preserveUpdatedAt = false}) async {
    final db = _requireDb();
    final stamped = preserveUpdatedAt
        ? paper
        : paper.withSyncTime(DateTime.now().millisecondsSinceEpoch);
    await db.insert(
      'papers',
      {
        'id': stamped.id,
        'kind': stamped.kind,
        'json': stamped.toJsonString(),
        'updated_at': stamped.updatedAt,
        'deleted_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _scheduleExport();
  }

  Future<void> savePapers(Iterable<Paper> papers) async {
    final db = _requireDb();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final paper in papers) {
        final stamped = paper.withSyncTime(now);
        await txn.insert(
          'papers',
          {
            'id': stamped.id,
            'kind': stamped.kind,
            'json': stamped.toJsonString(),
            'updated_at': stamped.updatedAt,
            'deleted_at': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _scheduleExport();
  }

  Future<void> deletePapers(Iterable<String> ids) async {
    final db = _requireDb();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.insert(
          'papers',
          {
            'id': id,
            'kind': 'deleted',
            'json': '{}',
            'updated_at': now,
            'deleted_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _scheduleExport();
  }

  Future<void> setSyncDirectory(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _syncDirectory = dir.path;
    await _setSetting('sync_directory', dir.path);
    await syncNow();
  }

  Future<String?> pickSyncDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose Tackboard SyncThing folder',
      initialDirectory: _syncDirectory,
    );
    if (selected == null) return null;
    await setSyncDirectory(selected);
    return selected;
  }

  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _importVisibleStateFiles();
      await exportState();
    } finally {
      _syncing = false;
    }
  }

  Future<void> exportState() async {
    final dir = Directory(_syncDirectory ?? '');
    if (_deviceId == null || !dir.existsSync()) return;

    final db = _requireDb();
    final rows = await db.query('papers');
    final papers = <Map<String, Object?>>[];
    final deleted = <Map<String, Object?>>[];
    for (final row in rows) {
      final deletedAt = row['deleted_at'];
      if (deletedAt is int) {
        deleted.add({'id': row['id'], 'deletedAt': deletedAt});
        continue;
      }
      try {
        papers.add(Paper.fromJsonString(row['json'] as String).toJson());
      } catch (_) {
        // Do not export a broken row.
      }
    }

    final state = {
      'schema': 1,
      'deviceId': _deviceId,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'papers': papers,
      'deleted': deleted,
    };

    final target = File(p.join(dir.path, 'tackboard_state_${_deviceId!}.json'));
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(const JsonEncoder.withIndent('  ').convert(state));
    if (target.existsSync()) target.deleteSync();
    await temp.rename(target.path);
  }

  void dispose() {
    _exportTimer?.cancel();
    final db = _db;
    if (db != null) unawaited(db.close());
  }

  Future<void> _importVisibleStateFiles() async {
    final syncDir = _syncDirectory;
    if (syncDir == null || syncDir.isEmpty) return;
    final dir = Directory(syncDir);
    if (!dir.existsSync()) return;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).startsWith('tackboard_state_'))
        .where((file) => p.extension(file.path).toLowerCase() == '.json');

    for (final file in files) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) {
          await _mergeState(decoded);
        } else if (decoded is Map) {
          await _mergeState(Map<String, Object?>.from(decoded));
        }
      } catch (_) {
        // SyncThing may expose a file while another device is still writing it.
      }
    }
  }

  Future<void> _mergeState(Map<String, Object?> state) async {
    final db = _requireDb();
    final rawDeleted = state['deleted'];
    final rawPapers = state['papers'];

    await db.transaction((txn) async {
      if (rawDeleted is List) {
        for (final entry in rawDeleted) {
          if (entry is! Map) continue;
          final id = entry['id']?.toString();
          final deletedAt = _intValue(entry['deletedAt'], 0);
          if (id == null || deletedAt <= 0) continue;
          final local = await txn.query(
            'papers',
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          final localStamp = local.isEmpty
              ? 0
              : max(
                  _intValue(local.first['updated_at'], 0),
                  _intValue(local.first['deleted_at'], 0),
                );
          if (deletedAt > localStamp) {
            await txn.insert(
              'papers',
              {
                'id': id,
                'kind': 'deleted',
                'json': '{}',
                'updated_at': deletedAt,
                'deleted_at': deletedAt,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }

      if (rawPapers is List) {
        for (final raw in rawPapers) {
          try {
            final paper = Paper.fromJson(raw);
            final local = await txn.query(
              'papers',
              where: 'id = ?',
              whereArgs: [paper.id],
              limit: 1,
            );
            final localUpdated = local.isEmpty ? 0 : _intValue(local.first['updated_at'], 0);
            final localDeleted = local.isEmpty ? 0 : _intValue(local.first['deleted_at'], 0);
            if (paper.updatedAt > localUpdated && paper.updatedAt > localDeleted) {
              await txn.insert(
                'papers',
                {
                  'id': paper.id,
                  'kind': paper.kind,
                  'json': paper.toJsonString(),
                  'updated_at': paper.updatedAt,
                  'deleted_at': null,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          } catch (_) {
            // Ignore one bad paper without rejecting the whole synced file.
          }
        }
      }
    });
  }

  void _scheduleExport() {
    _exportTimer?.cancel();
    _exportTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(syncNow());
    });
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) throw StateError('PaperRepository.init must complete first.');
    return db;
  }

  Future<String?> _setting(String key) async {
    final db = _requireDb();
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value']?.toString();
  }

  Future<void> _setSetting(String key, String value) async {
    await _requireDb().insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

String _newDeviceId() {
  final random = Random.secure();
  final bytes = List<int>.generate(8, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

int _intValue(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
