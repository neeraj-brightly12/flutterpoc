import 'package:flutter/foundation.dart'; // debugPrint
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/movie.dart';

class DBService {
  DBService._();
  static final DBService instance = DBService._();

  Database? _db;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'movies.db');

    final sw = Stopwatch()..start();
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE movies(
            id INTEGER PRIMARY KEY,
            title TEXT,
            overview TEXT,
            posterPath TEXT,
            page INTEGER
          );
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_movies_page ON movies(page);');
      },
    );
    sw.stop();
    debugPrint('[DB] openDatabase in ${sw.elapsedMilliseconds}ms');
  }

  Future<void> upsertMovies(List<Movie> movies) async {
    if (movies.isEmpty) return;
    final db = _db!;
    final sw = Stopwatch()..start();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final m in movies) {
        batch.insert('movies', m.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    sw.stop();
    debugPrint('[DB] upsertMovies(${movies.length}) in ${sw.elapsedMilliseconds}ms');
  }

  Future<List<Movie>> loadAllMovies() async {
    final db = _db!;
    final sw = Stopwatch()..start();
    final rows = await db.query('movies', orderBy: 'page ASC, id ASC');
    sw.stop();
    debugPrint('[DB] loadAllMovies() -> ${rows.length} rows in ${sw.elapsedMilliseconds}ms');
    return rows.map(Movie.fromMap).toList();
  }

  Future<int> countByPage(int page) async {
    final db = _db!;
    final res = await db.rawQuery('SELECT COUNT(*) AS c FROM movies WHERE page = ?', [page]);
    final c = res.first['c'];
    return c is int ? c : (c is num ? c.toInt() : 0);
  }

  Future<void> clear() async {
    final db = _db!;
    await db.delete('movies');
    debugPrint('[DB] clear()');
  }
}