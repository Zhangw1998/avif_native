library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:avif_native/avif_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

export 'package:avif_native/avif_native.dart';

/// A cacheable [ImageProvider] for the first frame of an AVIF image.
class AvifMemoryImage extends ImageProvider<AvifMemoryImage> {
  const AvifMemoryImage(this.bytes, {this.scale = 1});

  final Uint8List bytes;
  final double scale;

  @override
  Future<AvifMemoryImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    AvifMemoryImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _firstFrameCodec(key.bytes),
      scale: key.scale,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AvifMemoryImage &&
      identical(bytes, other.bytes) &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(identityHashCode(bytes), scale);
}

/// Displays static or animated AVIF data from memory, assets, or the network.
class AvifImage extends StatefulWidget {
  AvifImage.memory(
    Uint8List bytes, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.loadingBuilder,
    this.errorBuilder,
    this.semanticLabel,
  }) : _sourceKey = bytes,
       _load = ((_) async => bytes);

  AvifImage.asset(
    String asset, {
    super.key,
    AssetBundle? bundle,
    String? package,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.loadingBuilder,
    this.errorBuilder,
    this.semanticLabel,
  }) : _sourceKey = Object.hash(asset, package, bundle),
       _load = ((context) async {
         final key = package == null ? asset : 'packages/$package/$asset';
         final data = await (bundle ?? DefaultAssetBundle.of(context)).load(
           key,
         );
         return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
       });

  AvifImage.network(
    String url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.loadingBuilder,
    this.errorBuilder,
    this.semanticLabel,
  }) : _sourceKey = url,
       _load = ((_) async {
         final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
         return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
       });

  final Object _sourceKey;
  final Future<Uint8List> Function(BuildContext) _load;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object error, StackTrace? stack)?
  errorBuilder;
  final String? semanticLabel;

  @override
  State<AvifImage> createState() => _AvifImageState();
}

class _AvifImageState extends State<AvifImage> {
  List<ui.Image> _frames = const [];
  List<Duration> _durations = const [];
  Timer? _timer;
  Object? _error;
  StackTrace? _stack;
  int _frame = 0;
  int _generation = 0;
  int _loops = 0;
  int _repetitionCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_generation == 0) _reload();
  }

  @override
  void didUpdateWidget(AvifImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._sourceKey != widget._sourceKey) _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    _timer?.cancel();
    _disposeFrames();
    setState(() {
      _error = null;
      _stack = null;
      _frame = 0;
    });
    try {
      final decoded = decodeAvif(await widget._load(context));
      final images = <ui.Image>[];
      for (final frame in decoded.frames) {
        images.add(await _rgbaImage(frame));
      }
      if (!mounted || generation != _generation) {
        for (final image in images) {
          image.dispose();
        }
        return;
      }
      setState(() {
        _frames = images;
        _durations = [for (final frame in decoded.frames) frame.duration];
        _repetitionCount = decoded.repetitionCount;
        _loops = 0;
      });
      _schedule();
    } catch (error, stack) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _stack = stack;
      });
    }
  }

  void _schedule() {
    if (_frames.length < 2) return;
    final duration = _durations[_frame];
    _timer = Timer(
      duration > Duration.zero ? duration : const Duration(milliseconds: 100),
      () {
        if (!mounted) return;
        final next = (_frame + 1) % _frames.length;
        if (next == 0) {
          ++_loops;
          if (_repetitionCount >= 0 && _loops > _repetitionCount) return;
        }
        setState(() => _frame = next);
        _schedule();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return widget.errorBuilder?.call(context, error, _stack) ??
          ErrorWidget.builder(
            FlutterErrorDetails(exception: error, stack: _stack),
          );
    }
    if (_frames.isEmpty) {
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
    final image = RawImage(
      image: _frames[_frame],
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
    );
    return widget.semanticLabel == null
        ? image
        : Semantics(image: true, label: widget.semanticLabel, child: image);
  }

  void _disposeFrames() {
    for (final image in _frames) {
      image.dispose();
    }
    _frames = const [];
    _durations = const [];
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _disposeFrames();
    super.dispose();
  }
}

Future<ui.Codec> _firstFrameCodec(Uint8List bytes) async {
  final image = decodeAvif(bytes);
  final frame = image.frames.first;
  final buffer = await ui.ImmutableBuffer.fromUint8List(frame.rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: frame.width,
    height: frame.height,
    pixelFormat: ui.PixelFormat.rgba8888,
    rowBytes: frame.width * 4,
  );
  try {
    return await descriptor.instantiateCodec();
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

Future<ui.Image> _rgbaImage(AvifFrame frame) async {
  final codec = await _rawCodec(frame);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<ui.Codec> _rawCodec(AvifFrame frame) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(frame.rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: frame.width,
    height: frame.height,
    pixelFormat: ui.PixelFormat.rgba8888,
    rowBytes: frame.width * 4,
  );
  try {
    return await descriptor.instantiateCodec();
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}
