import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../data/face_db.dart';
import '../data/models.dart';
import 'face_crop.dart';
import 'face_embedder.dart';

/// Outcome of comparing one face against all saved people.
enum MatchKind {
  /// Clearly one saved person.
  known,

  /// Not similar enough to anyone saved.
  unknown,

  /// Similar to two different people; not safe to pick either.
  ambiguous,
}

class FaceMatch {
  const FaceMatch(this.kind, {this.personId, this.name, required this.score});
  final MatchKind kind;
  final int? personId;
  final String? name;

  /// Best cosine similarity found, in [-1, 1].
  final double score;
}

/// Single entry point the UI uses: computes embeddings, matches them against
/// saved faces, and saves new tagged faces. Notifies listeners when the set of
/// saved people changes.
class FaceRepository extends ChangeNotifier {
  FaceRepository._(this._db, this._embedder);

  final FaceDb _db;

  /// Null only in tests opened with [openForTest] (no face model).
  final FaceEmbedder? _embedder;

  /// Version of the crop + embedding method. Samples saved with a different
  /// version are ignored for matching because their vectors aren't comparable.
  /// v1: MobileFaceNet, unaligned crops.
  /// v2: MobileFaceNet, eye-aligned crops, mirror-averaged.
  /// v3: FaceNet-512, eye-aligned crops, mirror-averaged.
  static const int embedVersion = 3;

  /// Minimum cosine similarity to accept a face as a saved person.
  /// Raise it if strangers get someone's name; lower it if saved people stay
  /// "Unknown". Starting value for FaceNet-512; tune from the logged scores.
  static const double matchThreshold = 0.55;

  /// The best person must beat the next-best *different* person by at least
  /// this much. Otherwise the result is ambiguous.
  static const double minMargin = 0.10;

  List<FaceSample> _samples = [];
  int? _ownerId;

  /// The app owner's person id, or null until owner setup is done.
  int? get ownerId => _ownerId;
  Map<int, String> _names = {};

  static Future<FaceRepository> create() async {
    final repo = FaceRepository._(
      await FaceDb.open(),
      await FaceEmbedder.load(),
    );
    await repo._reload();
    return repo;
  }

  /// The database only, without the face model, for widget tests (on a
  /// computer, with a test database).
  @visibleForTesting
  static Future<FaceRepository> openForTest() async {
    final repo = FaceRepository._(await FaceDb.open(), null);
    await repo._reload();
    return repo;
  }

  Future<void> _reload() async {
    _samples = await _db.getSamples(embedVersion);
    _names = {
      for (final p in await _db.getPersons(embedVersion, includeOwner: true))
        p.id: p.name,
    };
    _ownerId = await _db.getOwnerId();
    notifyListeners();
  }

  List<double> embed(img.Image faceCrop) => _embedder!.embed(faceCrop);

  /// Current name of a saved person, or null if they were deleted.
  String? nameOf(int personId) => _names[personId];

  FaceMatch match(List<double> embedding) {
    // Best similarity per person, so several photos of one person can't push
    // another person out of second place.
    final best = <int, double>{};
    for (final s in _samples) {
      if (s.embedding.length != embedding.length) continue;
      var dot = 0.0;
      for (var i = 0; i < embedding.length; i++) {
        dot += embedding[i] * s.embedding[i];
      }
      final prev = best[s.personId];
      if (prev == null || dot > prev) best[s.personId] = dot;
    }
    if (best.isEmpty) return const FaceMatch(MatchKind.unknown, score: -1);

    final ranked = best.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first;
    final second = ranked.length > 1 ? ranked[1].value : -1.0;

    if (top.value < matchThreshold) {
      return FaceMatch(MatchKind.unknown, score: top.value);
    }
    if (top.value - second < minMargin) {
      return FaceMatch(MatchKind.ambiguous, score: top.value);
    }
    return FaceMatch(
      MatchKind.known,
      personId: top.key,
      name: _names[top.key] ?? '?',
      score: top.value,
    );
  }

  Future<List<Person>> getPersons() => _db.getPersons(embedVersion);

  Future<Person?> getPerson(int id) => _db.getPerson(id, embedVersion);

  Future<List<MoneyEntry>> getEntries(int personId) => _db.getEntries(personId);

  Future<void> addEntry(int personId, MoneyKind kind, int amountPaise) async {
    await _db.addEntry(personId, kind, amountPaise);
    notifyListeners();
  }

  Future<void> deleteEntry(int entryId) async {
    await _db.deleteEntry(entryId);
    notifyListeners();
  }

  Future<void> moveEntries(int personId, MoneyKind from, MoneyKind to) async {
    await _db.moveEntries(personId, from, to);
    notifyListeners();
  }

  Future<Person?> getOwner() async {
    final id = _ownerId;
    return id == null ? null : getPerson(id);
  }

  /// Saves the app owner with several face samples from one scan.
  /// With [existingId], that saved contact becomes the owner (their face
  /// was already saved), renamed to [name].
  Future<int> registerOwner({
    required String name,
    required List<(img.Image, List<double>)> faces,
    Uint8List? portraitJpeg,
    int? existingId,
  }) async {
    final id =
        existingId ??
        await _db.createPerson(name: name, lentPaise: 0, repaidPaise: 0);
    try {
      if (existingId != null) await _db.renamePerson(id, name);
      for (final (crop, emb) in faces) {
        await _db.addSample(
          personId: id,
          embedding: emb,
          jpeg: faceThumbnailJpeg(crop),
          embedVersion: embedVersion,
        );
      }
      if (portraitJpeg != null) await _db.setPhoto(id, portraitJpeg);
      // Last, so the owner only exists once everything above is saved.
      await _db.setOwner(id);
    } catch (_) {
      // Don't leave a half-made contact behind for a new owner. (A linked
      // existing contact is kept; it isn't marked as the owner.)
      if (existingId == null) {
        try {
          await _db.deletePerson(id);
        } catch (_) {}
      }
      await _reload();
      rethrow;
    }
    await _reload();
    return id;
  }

  /// Replaces the owner's saved face with a new scan.
  Future<void> updateOwnerFace({
    required List<(img.Image, List<double>)> faces,
    Uint8List? portraitJpeg,
  }) async {
    final id = _ownerId;
    if (id == null) return;
    await _db.deleteSamples(id);
    for (final (crop, emb) in faces) {
      await _db.addSample(
        personId: id,
        embedding: emb,
        jpeg: faceThumbnailJpeg(crop),
        embedVersion: embedVersion,
      );
    }
    if (portraitJpeg != null) await _db.setPhoto(id, portraitJpeg);
    await _reload();
  }

  /// Id of a saved person with this name (case-insensitive), or null.
  Future<int?> findPersonByName(String name) => _db.findPersonByName(name);

  /// Registers a new contact with their face so they are recognized in
  /// future scans. [portraitJpeg] is the profile photo shown on their page.
  Future<int> registerPerson({
    required String name,
    required List<double> embedding,
    required img.Image faceCrop,
    Uint8List? portraitJpeg,
    int lentPaise = 0,
    int repaidPaise = 0,
    int borrowedPaise = 0,
    String? notes,
    DateTime? reminder,
  }) async {
    final personId = await _db.createPerson(
      name: name,
      lentPaise: lentPaise,
      repaidPaise: repaidPaise,
      borrowedPaise: borrowedPaise,
      notes: notes,
      reminder: reminder,
    );
    await _db.addSample(
      personId: personId,
      embedding: embedding,
      jpeg: faceThumbnailJpeg(faceCrop),
      embedVersion: embedVersion,
    );
    if (portraitJpeg != null) await _db.setPhoto(personId, portraitJpeg);
    await _reload();
    return personId;
  }

  /// Adds another face sample to an existing person (improves recognition).
  Future<void> addFace({
    required int personId,
    required List<double> embedding,
    required img.Image faceCrop,
  }) async {
    await _db.addSample(
      personId: personId,
      embedding: embedding,
      jpeg: faceThumbnailJpeg(faceCrop),
      embedVersion: embedVersion,
    );
    await _reload();
  }

  /// Notes and reminder. Money is changed only through entries
  /// ([addEntry], [deleteEntry]) so totals always match the records.
  Future<void> updateDetails(
    int id, {
    String? notes,
    bool clearNotes = false,
    DateTime? reminder,
    bool clearReminder = false,
  }) async {
    await _db.updateDetails(
      id,
      notes: notes,
      clearNotes: clearNotes,
      reminder: reminder,
      clearReminder: clearReminder,
    );
    notifyListeners();
  }

  Future<void> setPhoto(
    int id,
    Uint8List jpeg, {
    bool onlyIfMissing = false,
  }) async {
    if (await _db.setPhoto(id, jpeg, onlyIfMissing: onlyIfMissing)) {
      notifyListeners();
    }
  }

  Future<void> renamePerson(int id, String name) async {
    await _db.renamePerson(id, name);
    await _reload();
  }

  Future<void> deletePerson(int id) async {
    await _db.deletePerson(id);
    await _reload();
  }
}
