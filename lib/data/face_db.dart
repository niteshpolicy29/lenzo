import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Local on-device storage for people and their face samples.
///
/// Tables:
///   persons(id, name, created_at, lent_paise, repaid_paise,
///           borrowed_paise, paid_back_paise, notes,
///           reminder_at, photo_path)
///   face_samples(id, person_id, embedding, image_path, created_at)
///   money_entries(id, person_id, kind, amount_paise, created_at, legacy)
///
/// Face crop images are written as JPEG files under `<app docs>/faces/`.
class FaceDb {
  FaceDb._(this._db, this._facesDir);

  final Database _db;
  final Directory _facesDir;

  static Future<FaceDb> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final facesDir = Directory(p.join(docs.path, 'faces'));
    await facesDir.create(recursive: true);

    final dbPath = p.join(await getDatabasesPath(), 'face_tag.db');
    // One-time copy of the database before upgrading to this version, kept
    // beside it.
    final backup = File('$dbPath.pre-v$_version.bak');
    final current = File(dbPath);
    if (await current.exists() && !await backup.exists()) {
      await current.copy(backup.path);
    }
    final db = await openDatabase(
      dbPath,
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Samples saved before v2 used unaligned crops; mark them as v1.
          await db.execute(
            'ALTER TABLE face_samples '
            'ADD COLUMN embed_version INTEGER NOT NULL DEFAULT 1',
          );
        }
        if (oldVersion < 3) {
          for (final column in _detailColumns) {
            await db.execute('ALTER TABLE persons ADD COLUMN $column');
          }
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE persons ADD COLUMN $_ownerColumn');
        }
        if (oldVersion < 5) {
          // New, separate direction. Existing repaid_paise values stay
          // repayments of money lent; nothing is reinterpreted.
          for (final column in _borrowColumns) {
            await db.execute('ALTER TABLE persons ADD COLUMN $column');
          }
        }
        if (oldVersion < 6) {
          await db.execute(_entriesTable);
          await db.execute(_entriesIndex);
          // Each stored total becomes one entry of the same kind, so every
          // amount keeps its meaning: a repayment stays a repayment.
          final rows = await db.query('persons');
          for (final r in rows) {
            for (final k in MoneyKind.values) {
              final v = (r[_columnOf[k]!] as int?) ?? 0;
              if (v == 0) continue;
              await db.insert('money_entries', {
                'person_id': r['id'],
                'kind': k.code,
                'amount_paise': v,
                'created_at': r['created_at'],
                'legacy': 1,
              });
            }
          }
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE persons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            ${[..._detailColumns, _ownerColumn, ..._borrowColumns].join(',\n            ')}
          )
        ''');
        await db.execute('''
          CREATE TABLE face_samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id INTEGER NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
            embedding TEXT NOT NULL,
            image_path TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            embed_version INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_samples_person ON face_samples(person_id)',
        );
        await db.execute(_entriesTable);
        await db.execute(_entriesIndex);
      },
    );
    return FaceDb._(db, facesDir);
  }

  /// Person columns added in DB v3. Money is stored in paise so totals add
  /// up exactly; the reminder is a local date as milliseconds since epoch.
  static const _detailColumns = [
    'lent_paise INTEGER NOT NULL DEFAULT 0',
    'repaid_paise INTEGER NOT NULL DEFAULT 0',
    'notes TEXT',
    'reminder_at INTEGER',
    'photo_path TEXT',
  ];

  /// DB v4: marks the app owner (1) among the people.
  static const _ownerColumn = 'is_owner INTEGER NOT NULL DEFAULT 0';

  static const _version = 6;

  /// DB v6: every money record, dated. The four total columns on persons
  /// are kept, and always recomputed from these (see [_recomputeTotals]).
  static const _entriesTable = '''
    CREATE TABLE IF NOT EXISTS money_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      person_id INTEGER NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      amount_paise INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      legacy INTEGER NOT NULL DEFAULT 0
    )
  ''';
  static const _entriesIndex =
      'CREATE INDEX IF NOT EXISTS idx_entries_person '
      'ON money_entries(person_id)';

  static const _columnOf = {
    MoneyKind.lent: 'lent_paise',
    MoneyKind.repaid: 'repaid_paise',
    MoneyKind.borrowed: 'borrowed_paise',
    MoneyKind.paidBack: 'paid_back_paise',
  };

  /// A person's money records, newest first.
  Future<List<MoneyEntry>> getEntries(int personId) async {
    final rows = await _db.query(
      'money_entries',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'created_at DESC, id DESC',
    );
    return [
      for (final r in rows)
        MoneyEntry(
          id: r['id'] as int,
          personId: r['person_id'] as int,
          kind: MoneyKind.fromCode(r['kind'] as String),
          amountPaise: r['amount_paise'] as int,
          at: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
          legacy: r['legacy'] == 1,
        ),
    ];
  }

  Future<void> addEntry(int personId, MoneyKind kind, int amountPaise) async {
    if (amountPaise <= 0) return;
    await _db.insert('money_entries', {
      'person_id': personId,
      'kind': kind.code,
      'amount_paise': amountPaise,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await _recomputeTotals(personId);
  }

  /// Deletes one record; returns its person's id, or null if not found.
  Future<int?> deleteEntry(int entryId) async {
    final rows = await _db.query(
      'money_entries',
      columns: ['person_id'],
      where: 'id = ?',
      whereArgs: [entryId],
    );
    if (rows.isEmpty) return null;
    final personId = rows.first['person_id'] as int;
    await _db.delete('money_entries', where: 'id = ?', whereArgs: [entryId]);
    await _recomputeTotals(personId);
    return personId;
  }

  /// Re-files all of a person's [from] records as [to]. Only done when the
  /// user explicitly asks to (reviewing records that disagree).
  Future<void> moveEntries(int personId, MoneyKind from, MoneyKind to) async {
    await _db.update(
      'money_entries',
      {'kind': to.code},
      where: 'person_id = ? AND kind = ?',
      whereArgs: [personId, from.code],
    );
    await _recomputeTotals(personId);
  }

  /// Sets the four total columns from the person's entries.
  Future<void> _recomputeTotals(int personId) async {
    final t = MoneyEntry.totals(await getEntries(personId));
    await _db.update(
      'persons',
      {for (final k in MoneyKind.values) _columnOf[k]!: t[k]},
      where: 'id = ?',
      whereArgs: [personId],
    );
  }

  /// DB v5: money borrowed from the person, and what I've paid back of it.
  static const _borrowColumns = [
    'borrowed_paise INTEGER NOT NULL DEFAULT 0',
    'paid_back_paise INTEGER NOT NULL DEFAULT 0',
  ];

  static const _personQuery = '''
      SELECT p.id, p.name, p.created_at, p.lent_paise, p.repaid_paise,
             p.borrowed_paise, p.paid_back_paise,
             p.notes, p.reminder_at, p.is_owner,
             COUNT(s.id) AS sample_count,
             COALESCE(SUM(s.embed_version = ?), 0) AS usable_count,
             COALESCE(p.photo_path,
               (SELECT image_path FROM face_samples
                  WHERE person_id = p.id ORDER BY id DESC LIMIT 1)) AS thumb
      FROM persons p
      LEFT JOIN face_samples s ON s.person_id = p.id
  ''';

  static Person _personFromRow(Map<String, Object?> r) {
    final reminder = r['reminder_at'] as int?;
    return Person(
      id: r['id'] as int,
      name: r['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      sampleCount: r['sample_count'] as int,
      usableSampleCount: r['usable_count'] as int,
      thumbnailPath: r['thumb'] as String?,
      lentPaise: r['lent_paise'] as int,
      repaidPaise: r['repaid_paise'] as int,
      borrowedPaise: r['borrowed_paise'] as int,
      paidBackPaise: r['paid_back_paise'] as int,
      notes: r['notes'] as String?,
      reminder: reminder == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(reminder),
      isOwner: r['is_owner'] == 1,
    );
  }

  /// All people. [embedVersion] is the version used for recognition now;
  /// [Person.usableSampleCount] counts only samples of that version.
  /// The owner is left out unless [includeOwner].
  Future<List<Person>> getPersons(
    int embedVersion, {
    bool includeOwner = false,
  }) async {
    final rows = await _db.rawQuery(
      '$_personQuery ${includeOwner ? '' : 'WHERE p.is_owner = 0'} '
      'GROUP BY p.id ORDER BY p.name COLLATE NOCASE',
      [embedVersion],
    );
    return rows.map(_personFromRow).toList();
  }

  /// One person, or null if they were deleted.
  Future<Person?> getPerson(int personId, int embedVersion) async {
    final rows = await _db.rawQuery(
      '$_personQuery WHERE p.id = ? GROUP BY p.id',
      [embedVersion, personId],
    );
    return rows.isEmpty ? null : _personFromRow(rows.first);
  }

  /// Id of a contact with this name (case-insensitive), or null. The owner
  /// isn't a contact and is never returned.
  Future<int?> findPersonByName(String name) async {
    final rows = await _db.query(
      'persons',
      columns: ['id'],
      where: 'name = ? COLLATE NOCASE AND is_owner = 0',
      whereArgs: [name.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Id of the app owner, or null before owner setup.
  Future<int?> getOwnerId() async {
    final rows = await _db.query(
      'persons',
      columns: ['id'],
      where: 'is_owner = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Makes [personId] the one app owner.
  Future<void> setOwner(int personId) async {
    await _db.transaction((txn) async {
      await txn.update('persons', {'is_owner': 0}, where: 'is_owner = 1');
      await txn.update(
        'persons',
        {'is_owner': 1},
        where: 'id = ?',
        whereArgs: [personId],
      );
    });
  }

  /// Removes all face samples of [personId] (rows and image files).
  Future<void> deleteSamples(int personId) async {
    final samples = await _db.query(
      'face_samples',
      columns: ['image_path'],
      where: 'person_id = ?',
      whereArgs: [personId],
    );
    await _db.delete(
      'face_samples',
      where: 'person_id = ?',
      whereArgs: [personId],
    );
    for (final s in samples) {
      final f = File(s['image_path'] as String);
      if (await f.exists()) await f.delete();
    }
  }

  /// Creates a person with their details and returns the new id.
  Future<int> createPerson({
    required String name,
    required int lentPaise,
    required int repaidPaise,
    int borrowedPaise = 0,
    String? notes,
    DateTime? reminder,
  }) {
    return _db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await txn.insert('persons', {
        'name': name.trim(),
        'created_at': now,
        'lent_paise': lentPaise,
        'repaid_paise': repaidPaise,
        'borrowed_paise': borrowedPaise,
        'notes': notes,
        'reminder_at': reminder?.millisecondsSinceEpoch,
      });
      for (final (kind, v) in [
        (MoneyKind.lent, lentPaise),
        (MoneyKind.repaid, repaidPaise),
        (MoneyKind.borrowed, borrowedPaise),
      ]) {
        if (v <= 0) continue;
        await txn.insert('money_entries', {
          'person_id': id,
          'kind': kind.code,
          'amount_paise': v,
          'created_at': now,
        });
      }
      return id;
    });
  }

  /// Updates the given details. Pass [clearReminder] to remove the reminder.
  Future<void> updateDetails(
    int personId, {
    String? notes,
    bool clearNotes = false,
    DateTime? reminder,
    bool clearReminder = false,
  }) async {
    final values = <String, Object?>{
      if (notes != null || clearNotes) 'notes': clearNotes ? null : notes,
      if (reminder != null || clearReminder)
        'reminder_at': clearReminder ? null : reminder!.millisecondsSinceEpoch,
    };
    if (values.isEmpty) return;
    await _db.update('persons', values, where: 'id = ?', whereArgs: [personId]);
  }

  /// Saves [jpeg] as the person's profile photo, replacing any old one.
  /// With [onlyIfMissing], keeps an existing photo. Returns whether the
  /// photo was saved.
  Future<bool> setPhoto(
    int personId,
    Uint8List jpeg, {
    bool onlyIfMissing = false,
  }) async {
    final old = await _db.query(
      'persons',
      columns: ['photo_path'],
      where: 'id = ?',
      whereArgs: [personId],
    );
    if (old.isEmpty) return false;
    final oldPath = old.first['photo_path'] as String?;
    if (onlyIfMissing && oldPath != null) return false;
    final file = File(
      p.join(
        _facesDir.path,
        'photo_p${personId}_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ),
    );
    await file.writeAsBytes(jpeg, flush: true);
    await _db.update(
      'persons',
      {'photo_path': file.path},
      where: 'id = ?',
      whereArgs: [personId],
    );
    if (oldPath != null) {
      final f = File(oldPath);
      if (await f.exists()) await f.delete();
    }
    return true;
  }

  /// Samples created with the given embedding version.
  Future<List<FaceSample>> getSamples(int embedVersion) async {
    final rows = await _db.query(
      'face_samples',
      where: 'embed_version = ?',
      whereArgs: [embedVersion],
    );
    return rows
        .map(
          (r) => FaceSample(
            id: r['id'] as int,
            personId: r['person_id'] as int,
            embedding: (jsonDecode(r['embedding'] as String) as List)
                .map((e) => (e as num).toDouble())
                .toList(),
            imagePath: r['image_path'] as String,
          ),
        )
        .toList();
  }

  /// Saves a face sample (embedding + JPEG crop) for [personId].
  Future<FaceSample> addSample({
    required int personId,
    required List<double> embedding,
    required Uint8List jpeg,
    required int embedVersion,
  }) async {
    final file = File(
      p.join(
        _facesDir.path,
        'p${personId}_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ),
    );
    await file.writeAsBytes(jpeg, flush: true);
    final id = await _db.insert('face_samples', {
      'person_id': personId,
      'embedding': jsonEncode(embedding),
      'image_path': file.path,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'embed_version': embedVersion,
    });
    return FaceSample(
      id: id,
      personId: personId,
      embedding: embedding,
      imagePath: file.path,
    );
  }

  Future<void> renamePerson(int personId, String name) async {
    await _db.update(
      'persons',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [personId],
    );
  }

  Future<void> deletePerson(int personId) async {
    final samples = await _db.query(
      'face_samples',
      columns: ['image_path'],
      where: 'person_id = ?',
      whereArgs: [personId],
    );
    final photo = await _db.query(
      'persons',
      columns: ['photo_path'],
      where: 'id = ?',
      whereArgs: [personId],
    );
    await _db.delete('persons', where: 'id = ?', whereArgs: [personId]);
    final paths = [
      for (final s in samples) s['image_path'] as String,
      for (final r in photo)
        if (r['photo_path'] case final String path) path,
    ];
    for (final path in paths) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }
}
