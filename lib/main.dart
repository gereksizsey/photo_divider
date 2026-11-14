import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'download.dart';
import 'split.dart';

void main() => runApp(const MaterialApp(title: 'Photo Divider', home: HomePage()));

enum Mode { horizontal, vertical, grid }

// shortcut: hard cap so a typo like 1000x1000 can't hang the tab; raise if real users need more.
const _maxPieces = 400;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _name = '';
  img.Image? _src;
  img.ImageFormat? _format;
  Uint8List? _preview;
  bool _busy = false;

  Mode _mode = Mode.horizontal;
  int _n = 3, _rows = 2, _cols = 3, _gapX = 0, _gapY = 0;
  OutFormat _out = OutFormat.same;
  int _quality = 100;

  int get _r => switch (_mode) { Mode.horizontal => 1, Mode.vertical => _n, Mode.grid => _rows };
  int get _c => switch (_mode) { Mode.horizontal => _n, Mode.vertical => 1, Mode.grid => _cols };
  String get _ext => outExt(_out, _format);
  String get _base => _name.contains('.') ? _name.substring(0, _name.lastIndexOf('.')) : _name;
  String _fileName(Piece p) => '${_base}_r${p.row}_c${p.col}.$_ext';

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    // Let the spinner paint first: decode/encode is pure Dart and blocks the UI thread on web.
    await Future.delayed(const Duration(milliseconds: 50));
    try {
      await work();
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null) return;
    await _run(() async {
      final bytes = await f.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _snack('Unsupported image format (HEIC is not supported in this demo yet)');
        return;
      }
      final src = img.bakeOrientation(decoded);
      setState(() {
        _name = f.name;
        _src = src;
        _format = img.findFormatForData(bytes);
        // Preview from the decoded image so it matches the pieces exactly (EXIF rotation, TIFF).
        _preview = img.encodePng(src.width > 1200 ? img.copyResize(src, width: 1200) : src, level: 1);
      });
    });
  }

  void _download(Piece p) => downloadBytes(encodePiece(_src!, p, _ext, _quality), _fileName(p));

  Future<void> _downloadAll(List<Piece> pieces) => _run(() async {
    for (final p in pieces) {
      _download(p);
      // Browsers drop back-to-back downloads fired in the same tick.
      await Future.delayed(const Duration(milliseconds: 200));
    }
  });

  Widget _intField(String label, int value, void Function(int) set) => SizedBox(
    width: 220,
    child: TextFormField(
      key: ValueKey(label), // fields swap when the mode changes; keep each one's own text
      initialValue: '$value',
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (s) => setState(() => set(int.tryParse(s) ?? 0)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final src = _src;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Photo Divider')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 16,
                    children: [
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.image), label: const Text('Pick image')),
                          if (src != null) Text('$_name  ·  ${src.width}×${src.height}'),
                        ],
                      ),
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
                      Wrap(
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
                      ),
                      if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      if (src != null)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 600),
                            child: AspectRatio(
                              aspectRatio: src.width / src.height,
                              child: CustomPaint(
                                foregroundPainter: _CutPainter(pieces, src.width, src.height),
                                child: Image.memory(_preview!, fit: BoxFit.fill, gaplessPlayback: true),
                              ),
                            ),
                          ),
                        ),
                      if (pieces.isNotEmpty) ...[
                        FilledButton.icon(
                          onPressed: () => _downloadAll(pieces),
                          icon: const Icon(Icons.download),
                          label: Text('Download all (${pieces.length})'),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in pieces)
                              ActionChip(
                                avatar: const Icon(Icons.download, size: 16),
                                label: Text(_fileName(p)),
                                onPressed: () => _run(() async => _download(p)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator())),
            ),
        ],
      ),
    );
  }
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
