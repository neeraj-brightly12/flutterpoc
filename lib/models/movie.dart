class Movie {
  final int id;
  final String title;
  final String overview;
  final String posterPath;
  final int page;

  Movie({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.page,
  });

  factory Movie.fromJson(Map<String, dynamic> j, int page) => Movie(
        id: j['id'] ?? 0,
        title: (j['title'] ?? j['name'] ?? '').toString(),
        overview: (j['overview'] ?? '').toString(),
        posterPath: (j['poster_path'] ?? '').toString(),
        page: page,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'overview': overview,
        'posterPath': posterPath,
        'page': page,
      };

  static Movie fromMap(Map<String, dynamic> m) => Movie(
        id: m['id'] as int,
        title: (m['title'] ?? '').toString(),
        overview: (m['overview'] ?? '').toString(),
        posterPath: (m['posterPath'] ?? '').toString(),
        page: (m['page'] ?? 0) as int,
      );
}