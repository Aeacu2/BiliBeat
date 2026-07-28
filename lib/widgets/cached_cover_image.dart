import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';

/// A cover image that downscales on decode and disk-caches a CDN-resized
/// thumbnail.
///
/// Performance notes:
///  * Requests a size-matched thumbnail from Bilibili's image CDN (which
///    supports `@{w}w_{h}h` resizing) instead of the full-resolution original,
///    cutting download bytes and decode cost dramatically in long lists.
///  * Uses one shared [HttpClient] so connections are pooled and reused rather
///    than spawning (and leaking) a new client per image.
class CachedCoverImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget? fallback;

  const CachedCoverImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  @override
  State<CachedCoverImage> createState() => _CachedCoverImageState();
}

class _CachedCoverImageState extends State<CachedCoverImage> {
  static final HttpClient _client = HttpClient()
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 8;

  // Avoid requesting absurdly large thumbnails.
  static const int _maxEdge = 1080;

  File? _localImageFile;
  bool _isLoading = true;
  late String _loadKey;
  bool _needsLoad = true;

  @override
  void initState() {
    super.initState();
    _loadKey = widget.url;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsLoad) {
      _needsLoad = false;
      _loadImage();
    }
  }

  @override
  void didUpdateWidget(covariant CachedCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadKey = widget.url;
      _loadImage();
    }
  }

  int get _targetW {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return (widget.width * dpr).round().clamp(1, _maxEdge);
  }

  int get _targetH {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return (widget.height * dpr).round().clamp(1, _maxEdge);
  }

  static bool _isLocalPath(String url) =>
      url.startsWith('/') || url.startsWith('file://');

  static String _localPathOf(String url) =>
      url.startsWith('file://') ? url.substring('file://'.length) : url;

  /// Append Bilibili CDN resize params when applicable.
  String _sizedUrl(String url, int w, int h) {
    if (url.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host;
    final isBili = host.contains('hdslb.com') ||
        host.contains('biliimg.com') ||
        host.contains('bilivideo.com') ||
        host.contains('bilibili.com');
    if (!isBili) return url;
    if (url.contains('@')) return url; // already parameterized
    return '$url@${w}w_${h}h_1e_1c.webp';
  }

  Future<void> _loadImage() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final String token = _loadKey;

    // Local file path (e.g. a user-picked custom cover): use it directly,
    // no download or CDN resizing needed.
    if (_isLocalPath(widget.url)) {
      final f = File(_localPathOf(widget.url));
      final exists = await f.exists();
      if (mounted && token == _loadKey) {
        setState(() {
          _localImageFile = exists ? f : null;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final w = _targetW;
      final h = _targetH;
      final fetchUrl = _sizedUrl(widget.url, w, h);

      final cacheDir = await getTemporaryDirectory();
      final md5Key = md5.convert(utf8.encode(fetchUrl)).toString();
      final file = File('${cacheDir.path}/img_$md5Key.png');

      if (await file.exists()) {
        if (mounted && token == _loadKey) {
          setState(() {
            _localImageFile = file;
            _isLoading = false;
          });
        }
        return;
      }

      final req = await _client.getUrl(Uri.parse(fetchUrl));
      req.headers.set('Referer', 'https://www.bilibili.com/');
      req.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      );
      final res = await req.close();

      if (res.statusCode == 200) {
        final sink = file.openWrite();
        await res.pipe(sink);
        if (mounted && token == _loadKey) {
          setState(() {
            _localImageFile = file;
            _isLoading = false;
          });
        }
      } else {
        await res.drain<void>();
        if (mounted && token == _loadKey) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted && token == _loadKey) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final targetCacheWidth = (widget.width * dpr).round();
    final targetCacheHeight = (widget.height * dpr).round();

    if (widget.url.startsWith('/') || widget.url.startsWith('file://')) {
      final path = widget.url.replaceFirst('file://', '');
      final localF = File(path);
      if (localF.existsSync()) {
        return Image.file(
          localF,
          width: widget.width,
          height: widget.height,
          cacheWidth: targetCacheWidth > 0 ? targetCacheWidth : null,
          cacheHeight: targetCacheHeight > 0 ? targetCacheHeight : null,
          fit: widget.fit,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      }
    }

    if (_localImageFile != null) {
      return Image.file(
        _localImageFile!,
        width: widget.width,
        height: widget.height,
        cacheWidth: targetCacheWidth > 0 ? targetCacheWidth : null,
        cacheHeight: targetCacheHeight > 0 ? targetCacheHeight : null,
        fit: widget.fit,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    }

    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C22),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
        ),
      );
    }

    return Image.network(
      _sizedUrl(widget.url, targetCacheWidth, targetCacheHeight),
      headers: const {
        'Referer': 'https://www.bilibili.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      },
      width: widget.width,
      height: widget.height,
      cacheWidth: targetCacheWidth > 0 ? targetCacheWidth : null,
      cacheHeight: targetCacheHeight > 0 ? targetCacheHeight : null,
      fit: widget.fit,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) => _buildFallback(),
    );
  }

  Widget _buildFallback() {
    return widget.fallback ??
        Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.accent.withValues(alpha: 0.35),
                const Color(0xFF1E1E24),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.music_note_rounded,
              color: AppColors.accent,
              size: (widget.width * 0.4).clamp(24.0, 80.0),
            ),
          ),
        );
  }
}
