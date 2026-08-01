import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// A cover image that downscales on decode and disk-caches a CDN-resized
/// thumbnail.
///
/// Performance notes:
///  * Requests a size-matched thumbnail from Bilibili's image CDN (which
///    supports `@{w}w_{h}h` resizing) instead of the full-resolution original,
///    cutting download bytes and decode cost dramatically in long lists.
///  * Uses one shared [HttpClient] so connections are pooled and reused rather
///    than spawning (and leaking) a new client per image.
///  * Never touches the filesystem synchronously during `build` — that used to
///    put a blocking `existsSync` on the raster path for every local cover.
class CachedCoverImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;

  const CachedCoverImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  /// Appends Bilibili CDN resize params when the host supports them.
  static String sizedUrl(String url, int w, int h) {
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

  static bool isLocalPath(String url) =>
      url.startsWith('/') || url.startsWith('file://');

  static String localPathOf(String url) =>
      url.startsWith('file://') ? url.substring('file://'.length) : url;

  @override
  State<CachedCoverImage> createState() => _CachedCoverImageState();
}

enum _CoverStatus { loading, ready, failed }

class _CachedCoverImageState extends State<CachedCoverImage> {
  static final HttpClient _client = HttpClient()
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 8;

  // Avoid requesting absurdly large thumbnails.
  static const int _maxEdge = 1080;

  File? _file;
  _CoverStatus _status = _CoverStatus.loading;
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
      setState(() {
        _file = null;
        _status = _CoverStatus.loading;
      });
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

  void _settle(String token, File? file) {
    if (!mounted || token != _loadKey) return;
    setState(() {
      _file = file;
      _status = file == null ? _CoverStatus.failed : _CoverStatus.ready;
    });
  }

  Future<void> _loadImage() async {
    if (widget.url.isEmpty) {
      _settle(_loadKey, null);
      return;
    }

    final String token = _loadKey;

    // Local file path (e.g. a user-picked custom cover): use it directly,
    // no download or CDN resizing needed.
    if (CachedCoverImage.isLocalPath(widget.url)) {
      final f = File(CachedCoverImage.localPathOf(widget.url));
      _settle(token, await f.exists() ? f : null);
      return;
    }

    try {
      final fetchUrl =
          CachedCoverImage.sizedUrl(widget.url, _targetW, _targetH);

      final cacheDir = await getTemporaryDirectory();
      final md5Key = md5.convert(utf8.encode(fetchUrl)).toString();
      final file = File('${cacheDir.path}/img_$md5Key.img');

      if (await file.exists() && await file.length() > 0) {
        _settle(token, file);
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

      if (res.statusCode != 200) {
        await res.drain<void>();
        _settle(token, null);
        return;
      }

      // Download to a temp sibling and rename into place, so a kill mid-write
      // can never leave a truncated file cached forever.
      final part = File('${file.path}.part');
      final sink = part.openWrite();
      try {
        await res.pipe(sink);
      } finally {
        await sink.close();
      }
      if (await part.length() == 0) {
        await part.delete();
        _settle(token, null);
        return;
      }
      await part.rename(file.path);
      _settle(token, file);
    } catch (_) {
      _settle(token, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Decode headroom: [ResizeImagePolicy.fit] fits the image *inside* the
    // box, but `BoxFit.cover` then scales by the box's *larger* ratio. Sizing
    // the decode box up by the widest cover we expect (16:9) keeps a landscape
    // image sharp when it is cropped to a square. It costs nothing for the
    // usual case: ResizeImage never upscales, so the decode is still capped at
    // the source, and CDN thumbnails already arrive at the requested square.
    const headroom = 16 / 9;
    final cacheW = (widget.width * dpr * headroom).round();
    final cacheH = (widget.height * dpr * headroom).round();

    late final Widget child;
    switch (_status) {
      case _CoverStatus.ready:
        child = Image(
          // Not `Image.file(cacheWidth:, cacheHeight:)`: passing both forces
          // an exact-size decode, which *stretches* anything whose aspect
          // ratio is not the box's. Bilibili's CDN hands back a square crop so
          // list thumbnails looked right, but a custom cover picked from disk
          // (or any URL the CDN does not resize) was squashed into the square
          // album art on the player page. `fit` preserves the aspect ratio and
          // lets [BoxFit.cover] do the cropping, as it does everywhere else.
          image: ResizeImage(
            FileImage(_file!),
            width: cacheW > 0 ? cacheW : null,
            height: cacheH > 0 ? cacheH : null,
            policy: ResizeImagePolicy.fit,
          ),
          key: ValueKey(_file!.path),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      case _CoverStatus.failed:
        child = _buildFallback();
      case _CoverStatus.loading:
        child = _buildPlaceholder();
    }

    return AnimatedSwitcher(
      duration: AppMotion.fast,
      switchInCurve: AppMotion.standard,
      child: SizedBox(
        key: ValueKey(_status),
        width: widget.width,
        height: widget.height,
        child: child,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF17171C),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: AppColors.textFaint,
          size: (widget.width * 0.28).clamp(14.0, 40.0),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
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
