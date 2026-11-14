import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'download.dart';
import 'drop.dart';
import 'heic.dart';
import 'split.dart';

part 'x_mode.dart';

/// App-wide so the spinner also covers the viewer route.
final _busy = ValueNotifier(false);

void main() => runApp(
  MaterialApp(
    title: 'Photo Divider',
    home: const HomePage(),
    builder: (context, child) => ValueListenableBuilder(
      valueListenable: _busy,
      builder: (context, busy, _) => Stack(
        children: [
          child!,
          if (busy)
            const Positioned.fill(
              child: ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator())),
            ),
        ],
      ),
    ),
  ),
);

// shortcut: preview/thumbnails/viewer use a copy capped at this size, so the viewer is true full size
// only up to ~16 MP photos; raise it if users need to inspect bigger ones (costs memory).
const _viewMax = 4096;

/// Downscaled copy for preview, thumbnails and viewer. Raw RGBA, so no slow PNG encode.
Future<ui.Image> _toView(img.Image src) {
  final wide = src.width >= src.height;
  final small = src.width > _viewMax || src.height > _viewMax
      ? img.copyResize(
          src,
          width: wide ? _viewMax : null,
          height: wide ? null : _viewMax,
          interpolation: img.Interpolation.linear,
        )
      : src;
  final rgba = small.convert(format: img.Format.uint8, numChannels: 4, noAnimation: true);
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba.toUint8List(), rgba.width, rgba.height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

enum Mode { horizontal, vertical, grid }

// shortcut: hard cap so a typo like 1000x1000 can't hang the tab; raise if real users need more.
const _maxPieces = 400;

/// Scrollable page, content centred and at most 900 px wide.
Widget _page(List<Widget> children) => ListView(
  padding: const EdgeInsets.all(16),
  children: [
    Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: children),
      ),
    ),
  ],
);

Widget _numField(
  String label,
  String value,
  void Function(String) onChanged, {
  bool decimal = false,
  bool enabled = true,
  String? hint,
  Key? key,
}) => SizedBox(
  width: 220,
  child: TextFormField(
    key: key ?? ValueKey(label), // fields swap when the mode changes; keep each one's own text
    initialValue: value,
    enabled: enabled,
    decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]'))],
    onChanged: onChanged,
  ),
);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _name = '';
  img.Image? _src;
  img.ImageFormat? _format;
  ui.Image? _view;

  Mode _mode = Mode.horizontal;
  int _n = 3, _rows = 2, _cols = 3, _gapX = 0, _gapY = 0;
  OutFormat _out = OutFormat.same;
  int _quality = 100;
  int _tab = 0; // 0: Normal, 1: For X.com

  int get _r => switch (_mode) { Mode.horizontal => 1, Mode.vertical => _n, Mode.grid => _rows };
  int get _c => switch (_mode) { Mode.horizontal => _n, Mode.vertical => 1, Mode.grid => _cols };
  String get _ext => outExt(_out, _format);
  String get _base => _name.contains('.') ? _name.substring(0, _name.lastIndexOf('.')) : _name;
  String _fileName(Piece p) => '${_base}_r${p.row}_c${p.col}.$_ext';

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() work) async {
    _busy.value = true;
    // Let the spinner paint first: decode/encode is pure Dart and blocks the UI thread on web.
    await Future.delayed(const Duration(milliseconds: 50));
    try {
      await work();
    } catch (e) {
      _snack('Error: $e');
    } finally {
      _busy.value = false;
    }
  }

  @override
  void initState() {
    super.initState();
    onDropOrPaste(_load);
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      // Explicit list: some desktop file dialogs hide .heic under a plain image/* filter.
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'heic', 'heif'],
    );
    if (f != null) await _load(f.name, f.readAsBytes);
  }

  Future<void> _load(String name, Future<Uint8List> Function() read) => _run(() async {
    var bytes = await read();
    if (looksLikeHeic(bytes)) {
      final png = await heicToPng(bytes);
      if (png == null) {
        _snack('Could not convert this HEIC/HEIF file');
        return;
      }
      bytes = png; // so "Same as input" gives PNG, as the spec says
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      _snack('Unsupported image format');
      return;
    }
    final src = img.bakeOrientation(decoded);
    // View from the decoded image so it matches the pieces exactly (EXIF rotation, TIFF).
    final view = await _toView(src);
    final old = _view;
    setState(() {
      _name = name;
      _src = src;
      _format = img.findFormatForData(bytes);
      _view = view;
    });
    old?.dispose();
  });

  void _openViewer(List<Piece> pieces, int start) {
    final src = _src!, view = _view!;
    var i = start;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => StatefulBuilder(
          builder: (context, setViewer) {
            final p = pieces[i];
            return Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                title: Text('${_fileName(p)}  (${i + 1}/${pieces.length})'),
                actions: [
                  IconButton(
                    tooltip: 'Download',
                    icon: const Icon(Icons.download),
                    onPressed: () => _run(() async => _download(p)),
                  ),
                ],
              ),
              body: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous',
                    color: Colors.white,
                    icon: const Icon(Icons.chevron_left, size: 40),
                    onPressed: i > 0 ? () => setViewer(() => i--) : null,
                  ),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: p.w / p.h,
                        child: CustomPaint(painter: _CropPainter(view, p, src.width, src.height)),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    color: Colors.white,
                    icon: const Icon(Icons.chevron_right, size: 40),
                    onPressed: i < pieces.length - 1 ? () => setViewer(() => i++) : null,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _download(Piece p) => downloadBytes(encodePiece(_src!, p, _ext, _quality), _fileName(p));

  /// [encode] runs once the spinner shows and returns name -> bytes in download order.
  Future<void> _downloadAll(Map<String, Uint8List> Function() encode) => _run(() async {
    final files = encode();
    if (!preferShare) return _downloadFiles(files);
    if (!isIOS) await _downloadFiles(files); // Android downloads fine; the share sheet comes on top
    if (tapStillActive) return _share(files);
    // Encoding/downloading outlasted the tap and the share sheet needs a recent one: ask for another.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${files.length} pieces ready'),
        duration: const Duration(minutes: 1),
        action: SnackBarAction(label: isIOS ? 'Save' : 'Share', onPressed: () => _run(() => _share(files))),
      ),
    );
  });

  /// On iOS the share sheet is the only way to save, so fall back to downloads if it refuses.
  Future<void> _share(Map<String, Uint8List> files) async {
    if (!await shareFiles(files) && isIOS) await _downloadFiles(files);
  }

  Future<void> _downloadFiles(Map<String, Uint8List> files) async {
    for (final MapEntry(key: name, value: bytes) in files.entries) {
      downloadBytes(bytes, name);
      // Browsers drop back-to-back downloads fired in the same tick.
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Widget _intField(String label, int value, void Function(int) set) =>
      _numField(label, '$value', (s) => setState(() => set(int.tryParse(s) ?? 0)));

  @override
  Widget build(BuildContext context) {
    final src = _src, view = _view;
    var pieces = <Piece>[];
    String? error;
    if (src != null) {
      if (_r * _c > _maxPieces) {
        error = 'Max $_maxPieces pieces';
      } else {
        try {
          pieces = computePieces(width: src.width, height: src.height, rows: _r, cols: _c, gapX: _gapX, gapY: _gapY);
        } on ArgumentError catch (e) {
          error = '${e.message}';
        }
      }
    }

    // Shared by both tabs: same picked image, same output format.
    final header = Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.image), label: const Text('Pick image')),
        if (src != null) Text('$_name  ·  ${src.width}×${src.height}'),
      ],
    );
    final formatControls = Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<OutFormat>(
          segments: const [
            ButtonSegment(value: OutFormat.same, label: Text('Same as input')),
            ButtonSegment(value: OutFormat.jpg, label: Text('JPG')),
            ButtonSegment(value: OutFormat.png, label: Text('PNG')),
          ],
          selected: {_out},
          onSelectionChanged: (s) => setState(() => _out = s.first),
        ),
        if (_ext == 'jpg')
          SizedBox(
            width: 300,
            child: Row(
              children: [
                Text('Quality $_quality'),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 100,
                    divisions: 99,
                    value: _quality.toDouble(),
                    onChanged: (v) => setState(() => _quality = v.round()),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Photo Divider'),
          bottom: TabBar(
            onTap: (i) => setState(() => _tab = i),
            tabs: const [Tab(text: 'Normal'), Tab(text: 'For X.com')],
          ),
        ),
        // IndexedStack keeps each tab's settings and scroll position while the other is shown.
        body: IndexedStack(
          index: _tab,
          children: [
            _page([
                  header,
                  SegmentedButton<Mode>(
                    segments: const [
                      ButtonSegment(value: Mode.horizontal, label: Text('Horizontal')),
                      ButtonSegment(value: Mode.vertical, label: Text('Vertical')),
                      ButtonSegment(value: Mode.grid, label: Text('Grid')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (_mode == Mode.grid) ...[
                        _intField('Rows', _rows, (v) => _rows = v),
                        _intField('Columns', _cols, (v) => _cols = v),
                      ] else
                        _intField('Count', _n, (v) => _n = v),
                      if (_mode != Mode.vertical) _intField('Gap between columns (px)', _gapX, (v) => _gapX = v),
                      if (_mode != Mode.horizontal) _intField('Gap between rows (px)', _gapY, (v) => _gapY = v),
                    ],
                  ),
                  formatControls,
                  if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (src != null)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 600),
                        child: AspectRatio(
                          aspectRatio: src.width / src.height,
                          child: CustomPaint(
                            foregroundPainter: _CutPainter(pieces, src.width, src.height),
                            child: RawImage(image: view, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                          ),
                        ),
                      ),
                    ),
                  if (pieces.isNotEmpty) ...[
                    FilledButton.icon(
                      onPressed: () => _downloadAll(
                        () => {for (final p in pieces) _fileName(p): encodePiece(src!, p, _ext, _quality)},
                      ),
                      icon: const Icon(Icons.download),
                      label: Text('Download all (${pieces.length})'),
                    ),
                    // Thumbnails laid out like the image, pulled apart; half the preview's height budget.
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 300 * src!.width / src.height),
                        child: Column(
                          spacing: 6,
                          children: [
                            for (var r = 0; r < _r; r++)
                              Row(
                                spacing: 6,
                                children: [
                                  for (var i = r * _c; i < (r + 1) * _c; i++)
                                    Expanded(
                                      flex: pieces[i].w, // same row height for every piece
                                      child: Tooltip(
                                        message: _fileName(pieces[i]),
                                        child: InkWell(
                                          onTap: () => _openViewer(pieces, i),
                                          child: AspectRatio(
                                            aspectRatio: pieces[i].w / pieces[i].h,
                                            child: CustomPaint(painter: _CropPainter(view!, pieces[i], src.width, src.height)),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
            ]),
            _XTab(
              header: header,
              formatControls: formatControls,
              src: src,
              view: view,
              base: _base,
              ext: _ext,
              quality: _quality,
              saveAll: _downloadAll,
            ),
          ],
        ),
      ),
    );
  }
}

/// One piece, cropped out of the downscaled view image ([w]x[h] is the full source size).
class _CropPainter extends CustomPainter {
  _CropPainter(this.view, this.p, this.w, this.h);
  final ui.Image view;
  final Piece p;
  final int w, h;

  @override
  void paint(Canvas canvas, Size size) {
    final kx = view.width / w, ky = view.height / h;
    canvas.drawImageRect(
      view,
      Rect.fromLTWH(p.x * kx, p.y * ky, p.w * kx, p.h * ky),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) => true;
}

/// Cut lines on the preview, gap areas shaded. Works in image pixel coordinates.
class _CutPainter extends CustomPainter {
  _CutPainter(this.pieces, this.w, this.h);
  final List<Piece> pieces;
  final int w, h;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / w;
    canvas.scale(k, size.height / h);
    final rects = [for (final p in pieces) Rect.fromLTWH(p.x.toDouble(), p.y.toDouble(), p.w.toDouble(), p.h.toDouble())];
    // Even-odd fill of (whole image + every piece) = only the gap areas.
    final gaps = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    for (final r in rects) {
      gaps.addRect(r);
    }
    canvas.drawPath(gaps, Paint()..color = const Color(0x99FF1744));
    final line = Paint()
      ..color = const Color(0xFFFF1744)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / k;
    for (final r in rects) {
      canvas.drawRect(r, line);
    }
  }

  @override
  bool shouldRepaint(_CutPainter old) => true;
}
