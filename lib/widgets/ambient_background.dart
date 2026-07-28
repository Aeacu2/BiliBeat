import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Full-screen ambient backdrop whose glow is derived from the current cover
/// art's dominant color — the signature "Apple Music" look. Falls back to the
/// brand pink when there is no cover or extraction fails.
///
/// Performance:
///  * The dominant color is extracted from a 24×24 decode (tiny) and cached per
///    URL, so it runs once per track.
///  * The glow lives in a [RepaintBoundary]; only the ~600 ms color transition
///    repaints, then it is static. The frosted overlay is built once.
class AmbientBackground extends StatefulWidget {
  final String? coverUrl;
  final Widget child;

  const AmbientBackground({
    super.key,
    this.coverUrl,
    required this.child,
  });

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> {
  static final HttpClient _client = HttpClient()
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 4;

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  static final Map<String, Color> _colorCache = {};
  static const int _maxCacheSize = 100;
  static const Color _fallback = AppColors.accent;

  Color _color = _fallback;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _resolve(widget.coverUrl);
  }

  @override
  void didUpdateWidget(covariant AmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) {
      _resolve(widget.coverUrl);
    }
  }

  Future<void> _resolve(String? url) async {
    if (url == null || url.isEmpty) {
      _apply(_fallback);
      return;
    }
    final cached = _colorCache[url];
    if (cached != null) {
      _apply(cached);
      return;
    }
    final token = ++_token;
    try {
      final color = await _extractDominantColor(url);
      // Evict oldest entries when cache grows too large.
      if (_colorCache.length >= _maxCacheSize) {
        _colorCache.remove(_colorCache.keys.first);
      }
      _colorCache[url] = color;
      if (mounted && token == _token) _apply(color);
    } catch (e) {
      debugPrint('Ambient color extraction failed: $e');
      if (mounted && token == _token) _apply(_fallback);
    }
  }

  void _apply(Color c) {
    if (c != _color && mounted) {
      setState(() => _color = c);
    }
  }

  /// Decodes a tiny thumbnail and averages its pixels, biased toward saturated
  /// regions so vivid artwork dominates over neutral areas.
  static Future<Color> _extractDominantColor(String url) async {
    final Uint8List bytes;
    if (url.startsWith('/') || url.startsWith('file://')) {
      final path =
          url.startsWith('file://') ? url.substring('file://'.length) : url;
      bytes = await File(path).readAsBytes();
    } else {
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set('Referer', 'https://www.bilibili.com/');
      req.headers.set('User-Agent', _userAgent);
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        throw Exception('HTTP ${res.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    }

    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 24,
      targetHeight: 24,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(); // rawRgba
    image.dispose();
    codec.dispose();
    if (byteData == null) return _fallback;

    double r = 0, g = 0, b = 0, wSum = 0;
    final pixelCount = byteData.lengthInBytes ~/ 4;
    for (int i = 0; i < pixelCount; i++) {
      final o = i * 4;
      final rr = byteData.getUint8(o);
      final gg = byteData.getUint8(o + 1);
      final bb = byteData.getUint8(o + 2);
      final aa = byteData.getUint8(o + 3);
      if (aa < 128) continue;

      final rF = rr / 255.0, gF = gg / 255.0, bF = bb / 255.0;
      final mx = rF > gF ? (rF > bF ? rF : bF) : (gF > bF ? gF : bF);
      final mn = rF < gF ? (rF < bF ? rF : bF) : (gF < bF ? gF : bF);
      final sat = mx == 0 ? 0.0 : (mx - mn) / mx;

      final w = 0.15 + sat * sat; // emphasize vivid pixels
      r += rr * w;
      g += gg * w;
      b += bb * w;
      wSum += w;
    }
    if (wSum == 0) return _fallback;

    final base = Color.fromARGB(
      255,
      (r / wSum).round().clamp(0, 255),
      (g / wSum).round().clamp(0, 255),
      (b / wSum).round().clamp(0, 255),
    );

    // Push saturation/lightness into an elegant, glow-friendly range.
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.45, 0.85))
        .withLightness(hsl.lightness.clamp(0.38, 0.6))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final blob = size.longestSide * 0.85;

    return Stack(
      children: [
        // Animated, color-derived glow (isolated so it caches between changes).
        Positioned.fill(
          child: RepaintBoundary(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(begin: _fallback, end: _color),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, animated, _) {
                final c = animated ?? _fallback;
                final c2 = HSLColor.fromColor(c)
                    .withLightness(
                        (HSLColor.fromColor(c).lightness + 0.12).clamp(0.0, 0.7))
                    .toColor();
                return Stack(
                  children: [
                    Container(color: AppColors.background),
                    Positioned(
                      top: -blob * 0.28,
                      left: -blob * 0.22,
                      width: blob,
                      height: blob,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [c.withValues(alpha: 0.55), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -blob * 0.3,
                      right: -blob * 0.25,
                      width: blob * 1.05,
                      height: blob * 1.05,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [c2.withValues(alpha: 0.4), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // Static frosted overlay: diffuses the glow + deepens for legibility.
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.black30,
                    AppColors.black55,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Foreground content.
        Positioned.fill(child: widget.child),
      ],
    );
  }
}
