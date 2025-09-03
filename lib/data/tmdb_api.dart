import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:http/http.dart' as http;

import '../models/movie.dart';

class TMDbApi {
  TMDbApi._();
  static final TMDbApi instance = TMDbApi._();

  static const String _bearer =
      'Bearer eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI1NWFlNGRmZTY3NTRlNzhkODI1OTAyMDg5NWRlNzRjZCIsIm5iZiI6MTc1NjM2NzM3OC41MjgsInN1YiI6IjY4YjAwYTEyNDA0NDYzMDg5ZTBmOTFkNSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.rcLVMF3EHzaXtRCadYaRb-MSq3Ef1JTKUEwGkeH4xJM';
  static const String _apiKey = '55ae4dfe6754e78d8259020895de74cd';
  static const String _base = 'https://api.themoviedb.org/3/movie/popular';

  Future<({List<Movie> movies, int totalPages})> fetchPopular({required int page}) async {
    final uri = Uri.parse('$_base?page=$page&api_key=$_apiKey');
    final sw = Stopwatch()..start();
    debugPrint('[HTTP] → GET $uri');

    try {
      final resp = await http
          .get(uri, headers: {
            'Authorization': _bearer,
            'Accept': 'application/json',
          })
          .timeout(const Duration(seconds: 6));

      sw.stop();
      debugPrint('[HTTP] ← ${resp.statusCode} in ${sw.elapsedMilliseconds}ms, '
          'bytes: ${resp.bodyBytes.length}');

      if (resp.statusCode != 200) {
        throw HttpException('TMDb HTTP ${resp.statusCode}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final totalPages = (data['total_pages'] ?? 1) as int;
      final results = (data['results'] as List?) ?? const [];
      final movies = results
          .map((e) => Movie.fromJson(e as Map<String, dynamic>, page))
          .toList();

      return (movies: movies, totalPages: totalPages);
    } on TimeoutException {
      throw const SocketException('Network timeout');
    } on http.ClientException catch (e) {
      throw SocketException('Client error: ${e.message}');
    } on SocketException {
      rethrow;
    }
  }

  static String posterUrl(String posterPath, {String size = 'w185'}) {
    if (posterPath.isEmpty) return '';
    return 'https://image.tmdb.org/t/p/$size$posterPath';
  }
}