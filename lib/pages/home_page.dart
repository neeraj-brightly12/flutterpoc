import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart'; // for PaintingBinding image cache
import 'package:cached_network_image/cached_network_image.dart';

import '../data/db_service.dart';
import '../data/tmdb_api.dart';
import '../data/network_service.dart';
import '../models/movie.dart';
import '../widgets/status_chip.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Movie> _movies = [];
  bool _initialLoadedFromDb = false;

  int _currentPage = 0;
  int _maxPages = 5;
  bool _loading = false;
  bool _reachedEnd = false;
  bool _isOnline = true;

  // Track which pages we have fetched/are fetching to avoid duplicates.
  final Set<int> _requestedPages = <int>{};
  final Set<int> _fetchedPages = <int>{};

  late final ScrollController _scroll;
  StreamSubscription<bool>? _netSub;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_onScroll);

    _isOnline = NetworkService.instance.isOnline;

    // React to connectivity changes.
    _netSub = NetworkService.instance.onStatus.listen((online) async {
      if (!mounted) return;

      if (online) {
        // We’re back online: clear RAM image cache and evict base URLs from disk cache
        // so a plain base URL load will fetch fresh copies (no query params used).
        PaintingBinding.instance.imageCache.clearLiveImages();
        PaintingBinding.instance.imageCache.clear();

        // Evict each movie poster by its BASE URL key (works with strict servers).
        for (final m in _movies) {
          final base = TMDbApi.posterUrl(m.posterPath, size: 'w185');
          if (base.isNotEmpty) {
            await CachedNetworkImage.evictFromCache(base);
          }
        }
      }

      if (mounted) {
        setState(() {
          _isOnline = online;
          // Do NOT trigger a load here; scrolling will pick it up,
          // and pull-to-refresh still works.
        });
      }
    });

    _boot();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _netSub?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    // Show cached rows immediately (offline-first).
    final sw = Stopwatch()..start();
    final cached = await DBService.instance.loadAllMovies();
    sw.stop();
    // ignore: avoid_print
    print('[DB] loadAllMovies() -> ${cached.length} rows in ${sw.elapsedMilliseconds}ms');

    if (!mounted) return;
    setState(() {
      _movies
        ..clear()
        ..addAll(cached);
      _initialLoadedFromDb = true;
    });

    // Seed fetched pages from cached rows so we don’t refetch them.
    _fetchedPages
      ..clear()
      ..addAll(_movies.map((m) => m.page).where((p) => p > 0).toSet());
    _currentPage = _fetchedPages.isEmpty ? 0 : (_fetchedPages.reduce((a, b) => a > b ? a : b));

    // After first frame, if online and nothing loaded yet, fetch page 1.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isOnline && _currentPage == 0) {
        _loadNextPage(forceFirst: true);
      }
    });
  }

  void _onScroll() {
    if (!_isOnline || _loading || _reachedEnd) return;
    if (_currentPage >= _maxPages) {
      _reachedEnd = true;
      return;
    }
    // Trigger next page when near the bottom.
    const thresholdPx = 600.0;
    if (_scroll.position.pixels + thresholdPx >= _scroll.position.maxScrollExtent) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage({bool forceFirst = false}) async {
    if (_loading || !_isOnline) return;

    final next = forceFirst ? 1 : _currentPage + 1;
    if (next > _maxPages) {
      setState(() => _reachedEnd = true);
      return;
    }
    if (_requestedPages.contains(next) || _fetchedPages.contains(next)) {
      return; // already in-flight or fetched
    }

    _requestedPages.add(next);
    setState(() => _loading = true);

    // ignore: avoid_print
    print('[PAGE] requesting page $next …');
    try {
      final httpSw = Stopwatch()..start();
      final r = await TMDbApi.instance.fetchPopular(page: next);
      httpSw.stop();
      // ignore: avoid_print
      print('[PAGE] page $next fetched=${r.movies.length} in ${httpSw.elapsedMilliseconds}ms');

      final capped = r.totalPages < 5 ? r.totalPages : 5;
      final items = r.movies;

      if (!mounted) return;
      setState(() {
        _maxPages = capped;
        _currentPage = next;
        _fetchedPages.add(next);
        _movies.addAll(items);
      });

      final dbSw = Stopwatch()..start();
      await DBService.instance.upsertMovies(items);
      dbSw.stop();
      // ignore: avoid_print
      print('[DB] upsertMovies(${items.length}) in ${dbSw.elapsedMilliseconds}ms');
    } on SocketException catch (e) {
      if (!mounted) return;
      // ignore: avoid_print
      print('[PAGE] offline: ${e.message}');
      if (_movies.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Offline: ${e.message}')));
      }
    } catch (e) {
      if (!mounted) return;
      // ignore: avoid_print
      print('[PAGE] error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error: $e')));
    } finally {
      _requestedPages.remove(next);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (!_isOnline) {
      // Offline: just reload what’s in DB.
      final cached = await DBService.instance.loadAllMovies();
      if (!mounted) return;
      setState(() {
        _movies
          ..clear()
          ..addAll(cached);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Offline: showing cached data')));
      return;
    }

    // Online: reset pagination state and fetch fresh page 1.
    setState(() {
      _currentPage = 0;
      _fetchedPages.clear();
      _requestedPages.clear();
      _reachedEnd = false;
      _maxPages = 5;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isOnline) _loadNextPage(forceFirst: true);
    });
  }

  Future<void> _retryImages() async {
    // Manually clear caches and let base URLs re-download when online.
    PaintingBinding.instance.imageCache.clearLiveImages();
    PaintingBinding.instance.imageCache.clear();

    for (final m in _movies) {
      final base = TMDbApi.posterUrl(m.posterPath, size: 'w185');
      if (base.isNotEmpty) {
        await CachedNetworkImage.evictFromCache(base);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isOnline ? 'Popular Movies' : 'Popular Movies (Offline)'),
        actions: [
          const Padding(padding: EdgeInsets.only(right: 8), child: StatusChip()),
          IconButton(
            tooltip: 'Retry images',
            onPressed: _retryImages,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
      // floatingActionButton: FloatingActionButton.extended(
      //   onPressed: _refresh,
      //   icon: const Icon(Icons.sync),
      //   label: const Text('Refresh'),
      // ),
    );
  }

  Widget _buildBody() {
    if (!_initialLoadedFromDb && _movies.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_movies.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scroll,
          children: [
            const SizedBox(height: 160),
            Text(
              _isOnline ? 'No data yet. Pull to refresh.' : 'Offline. No cached data found.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (!_isOnline)
              Center(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final cached = await DBService.instance.loadAllMovies();
                    if (!mounted) return;
                    setState(() {
                      _movies
                        ..clear()
                        ..addAll(cached);
                    });
                  },
                  icon: const Icon(Icons.offline_pin),
                  label: const Text('Load cached'),
                ),
              )
            else
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _isOnline) _loadNextPage(forceFirst: true);
                    });
                  },
                  child: const Text('Load Page 1'),
                ),
              ),
            const SizedBox(height: 600),
          ],
        ),
      );
    }

    // Card-like row layout (consistent poster size).
    const posterW = 88.0;
    const posterH = posterW * 1.5; // 2:3

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _movies.length + (_loading ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          if (i >= _movies.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final m = _movies[i];
          final base = TMDbApi.posterUrl(m.posterPath, size: 'w185');

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Card(
              elevation: 2,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PosterThumb(
                      url: base, // ALWAYS base URL (mock-friendly)
                      width: posterW,
                      height: posterH,
                      radius: 12,
                      fit: BoxFit.cover,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.overview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Poster that reserves a fixed geometry and shows a soft placeholder.
/// Uses ONLY base URL (no query params). Freshness is enforced by
/// evicting the base URL when network returns.
class _PosterThumb extends StatelessWidget {
  final String url;             // base poster URL
  final double width;
  final double height;
  final double radius;
  final BoxFit fit;

  const _PosterThumb({
    required this.url,
    required this.width,
    required this.height,
    this.radius = 10,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _placeholder();
    }
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: url,                 // no ?net, no custom cacheKey
          fit: fit,
          // Use ONLY one of the builders to avoid the OctoImage assertion.
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _placeholder(),
          memCacheWidth: (width * MediaQuery.of(context).devicePixelRatio).round(),
          memCacheHeight: (height * MediaQuery.of(context).devicePixelRatio).round(),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x11000000),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: const Icon(Icons.image, size: 28, color: Color(0x55000000)),
    );
  }
}