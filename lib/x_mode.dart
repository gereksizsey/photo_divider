part of 'main.dart';

// Measured with Chrome DevTools on x.com desktop (side-by-side photo gallery). Not guaranteed on
// other screens, zoom levels or X font sizes: that's what Manual gap is for.
const _xGapCss = 5.33, _xHeightCss = 703.85;
// shortcut: corner radius is a guess (X's usual 16 px media rounding); measure it and change it here.
const _xRadius = 16.0;
const _xFrame = 600.0; // preview width in CSS px: x.com desktop timeline column
const _xInspector = false; // Seam Inspector kept in code but hidden from users; true shows it again

/// Source columns [from, to) wanted from a full-resolution crop of columns [first, last) (null while decoding).
typedef _Cols = ({ui.Image? image, int first, int last, double from, double to});

/// "For X.com" tab: 1 row of photos, cut so X's gap hides exactly the skipped strip.
class _XTab extends StatefulWidget {
  const _XTab({
    required this.header,
    required this.formatControls,
    required this.src,
    required this.view,
    required this.base,
    required this.ext,
    required this.quality,
    required this.saveAll,
  });

  final Widget header, formatControls;
  final img.Image? src;
  final ui.Image? view;
  final String base, ext;
  final int quality;
  final Future<void> Function(Map<String, Uint8List> Function() encode, {bool share}) saveAll;

  @override
  State<_XTab> createState() => _XTabState();
}

class _XTabState extends State<_XTab> {
  int _n = 3, _outH = 0; // 0: keep the source height, no resampling
  bool _auto = true;
  double _gapCss = _xGapCss, _heightCss = _xHeightCss; // used in Manual mode
  bool _before = false; // visualizer: plain split instead of the compensated one
  bool _mark = true, _guides = true;
  int _seam = 0, _zoom = 4;
  Offset _pan = Offset.zero; // inspector: CSS px from the seam's centre to the panel's centre
  final _strips = <(int, int), ui.Image?>{}; // inspector crops by source columns
  final _used = <(int, int)>{};

  double get _g => _auto ? _xGapCss : _gapCss;
  double get _hd => _auto ? _xHeightCss : _heightCss;


  @override
  void didUpdateWidget(_XTab old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) _dropStrips({});
  }

  @override
  void dispose() {
    _dropStrips({});
    super.dispose();
  }

  void _dropStrips(Set<(int, int)> keep) {
    for (final k in _strips.keys.where((k) => !keep.contains(k)).toList()) {
      _strips.remove(k)?.dispose();
    }
  }

  /// Full-resolution crop for the inspector: the shared view image is downscaled, too coarse at 8x.
  _Cols _cols(double from, double to) {
    final src = widget.src!;
    final first = max(0, from.floor()), last = min(src.width, to.ceil());
    final key = (first, last);
    _used.add(key);
    if (!_strips.containsKey(key)) {
      _strips[key] = null;
      _toView(img.copyCrop(src, x: first, y: 0, width: last - first, height: src.height)).then((i) {
        if (mounted && widget.src == src && _strips.containsKey(key) && _strips[key] == null) {
          setState(() => _strips[key] = i);
        } else {
          i.dispose();
        }
      });
    }
    return (image: _strips[key], first: first, last: last, from: from, to: to);
  }

  String _fileName(int i) => '${widget.base}_${'${i + 1}'.padLeft('$_n'.length, '0')}.${widget.ext}';

  void _saveAll(img.Image src, List<Piece> pieces, int w, int h, {bool share = false}) => widget.saveAll(share: share, () {
    // Resample once, only when another output height was asked for; otherwise crop the original pixels.
    final s = h == src.height
        ? src
        : img.copyResize(
            src,
            width: w,
            height: h,
            interpolation: h < src.height ? img.Interpolation.average : img.Interpolation.cubic,
          );
    return {for (final (i, p) in pieces.indexed) _fileName(i): encodePiece(s, p, widget.ext, widget.quality)};
  });

  Widget _chip(String label, bool on, void Function(bool) set) =>
      FilterChip(label: Text(label), selected: on, onSelected: (v) => setState(() => set(v)));

  @override
  Widget build(BuildContext context) {
    final src = widget.src, view = widget.view;
    final theme = Theme.of(context);
    final errors = <String>{};
    List<Piece> attempt(List<Piece> Function() f) {
      try {
        return f();
      } on ArgumentError catch (e) {
        errors.add('${e.message}');
        return const [];
      }
    }

    // Everything below is in output px: w x h is the image the pieces are cut from.
    var w = 0, h = 0;
    double? gap; // output px X hides at each seam
    var plain = const <Piece>[], comp = const <Piece>[];
    if (src != null) {
      h = _outH > 0 ? _outH : src.height;
      w = max(1, (src.width * h / src.height).round());
      if (_n > _maxPieces) {
        errors.add('Max $_maxPieces pieces');
      } else if (w * h > 100e6) {
        errors.add('Output too large (max 100 megapixels)');
      } else {
        try {
          gap = xSourceGap(cssGap: _g, cssHeight: _hd, imageHeight: h);
        } on ArgumentError catch (e) {
          errors.add('${e.message}');
        }
        plain = attempt(() => computePieces(width: w, height: h, rows: 1, cols: _n));
        final g = gap;
        if (g != null) comp = attempt(() => xPieces(width: w, height: h, n: _n, gap: g));
      }
    }
    final ready = src != null && view != null && plain.isNotEmpty && comp.isNotEmpty;
    final seam = min(_seam, _n - 2);
    final small = theme.textTheme.bodySmall;

    _used.clear();
    final children = <Widget>[
      widget.header,
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _numField('Photos', '$_n', (s) => setState(() => _n = int.tryParse(s) ?? 0)),
          _numField(
            'Output height (px)',
            _outH > 0 ? '$_outH' : '',
            (s) => setState(() => _outH = int.tryParse(s) ?? 0),
            hint: src == null ? null : '${src.height}', // empty = original height
          ),
        ],
      ),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Automatic'), tooltip: 'Recommended: the values measured on x.com'),
          ButtonSegment(value: false, label: Text('Manual'), tooltip: 'Type your own gap and display height'),
        ],
        selected: {_auto},
        onSelectionChanged: (s) => setState(() => _auto = s.first),
      ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _numField(
            'Twitter gap (CSS px)',
            '$_g',
            (s) => setState(() => _gapCss = double.tryParse(s) ?? 0),
            decimal: true,
            enabled: !_auto,
            key: ValueKey('gap$_auto'),
          ),
          _numField(
            'Twitter display height (CSS px)',
            '$_hd',
            (s) => setState(() => _heightCss = double.tryParse(s) ?? 0),
            decimal: true,
            enabled: !_auto,
            key: ValueKey('height$_auto'),
          ),
          if (gap != null)
            _numField(
              'Source gap (px)',
              gap.toStringAsFixed(2),
              (_) {},
              enabled: false,
              key: ValueKey('source$gap'), // read-only; new key so it shows each new value
            ),
        ],
      ),
      widget.formatControls,
      for (final e in errors) Text(e, style: TextStyle(color: theme.colorScheme.error)),
      if (comp.isNotEmpty)
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _saveAll(src!, comp, w, h),
              icon: const Icon(Icons.download),
              label: Text('Download all (${comp.length})'),
            ),
            if (preferShare && !isIOS)
              OutlinedButton.icon(
                onPressed: () => _saveAll(src!, comp, w, h, share: true),
                icon: const Icon(Icons.share),
                label: const Text('Share'),
              ),
          ],
        ),
      if (ready) ...[
        Text('Twitter Visualizer', style: theme.textTheme.titleLarge),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Before')),
            ButtonSegment(value: false, label: Text('After')),
          ],
          selected: {_before},
          onSelectionChanged: (s) => setState(() => _before = s.first),
        ),
        // Scales the whole card together, so gap and photos keep X's proportions on narrow screens.
        Center(child: FittedBox(fit: BoxFit.scaleDown, child: _tweet(_before ? plain : comp, w, h))),
        if (_xInspector && _n > 1) ...[
          Text('Seam Inspector', style: theme.textTheme.titleLarge),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<int>(
                value: seam,
                items: [
                  for (var i = 0; i < _n - 1; i++)
                    DropdownMenuItem(value: i, child: Text('Photos ${i + 1} | ${i + 2}')),
                ],
                onChanged: (v) => setState(() {
                  _seam = v!;
                  _pan = Offset.zero;
                }),
              ),
              SegmentedButton<int>(
                segments: [for (final z in const [1, 2, 4, 8]) ButtonSegment(value: z, label: Text('$z×'))],
                selected: {_zoom},
                onSelectionChanged: (s) => setState(() => _zoom = s.first),
              ),
              _chip('Mark gap', _mark, (v) => _mark = v),
              _chip('Guides', _guides, (v) => _guides = v),
            ],
          ),
          _seamPanel('Original split', plain, seam, h, gap!),
          _seamPanel('Gap compensated', comp, seam, h, gap),
          Text(
            'Drag to pan. 1× is x.com desktop size; the pixels around the seam come from the full-size photo.',
            style: small,
          ),
        ],
      ],
    ];
    _dropStrips(_used);
    return _page(children);
  }

  /// X's gallery rule: every photo the same CSS height, width from its own aspect ratio, a fixed CSS gap.
  Widget _tweet(List<Piece> ps, int w, int h) {
    const sub = Color(0xFF536471);
    final view = widget.view!;
    const left = 64.0; // avatar column, like a real post

    return Container(
      width: _xFrame,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFEFF3F4))),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFF0F1419), fontSize: 15, height: 1.33),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                spacing: 8,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: sub,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.person),
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Your Name', style: TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: ' @yourname · 1m', style: TextStyle(color: sub)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ScrollConfiguration(
              // Mouse drag scrolls the row too, not only trackpad / shift+wheel.
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: ui.PointerDeviceKind.values.toSet()),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: left, right: 16),
                child: Row(
                  spacing: _g,
                  children: [
                    for (final p in ps)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(_xRadius),
                        child: SizedBox(
                          width: xDisplayWidth(p, _hd),
                          height: _hd,
                          child: CustomPaint(painter: _CropPainter(view, p, w, h)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(left, 12, 16, 0),
              child: IconTheme(
                data: IconThemeData(color: sub, size: 19),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.chat_bubble_outline),
                    Icon(Icons.repeat),
                    Icon(Icons.favorite_border),
                    Icon(Icons.bar_chart),
                    Icon(Icons.bookmark_border),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// End of photo [seam], X's gap, start of the next photo, zoomed around the gap.
  Widget _seamPanel(String title, List<Piece> ps, int seam, int h, double gap) {
    final src = widget.src!;
    final a = ps[seam], b = ps[seam + 1];
    final skipped = b.x - a.x - a.w; // output px left out between the two photos
    final off = (gap - skipped).abs(); // what X hides minus what the cut skipped
    final q = src.height / h; // source px per output px
    final reach = 200 * h / _hd; // output px shown each side: 200 CSS px
    final aEnd = a.x + a.w;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          '$title · skips $skipped px, X hides ${gap.toStringAsFixed(2)} px → ${off.toStringAsFixed(2)} px '
          '(${(off * _hd / h).toStringAsFixed(2)} CSS px) out of line',
        ),
        GestureDetector(
          // Separate axes (not pan) so a vertical drag here beats the page's own scrolling.
          onHorizontalDragUpdate: (d) => setState(() => _pan -= Offset(d.delta.dx / _zoom, 0)),
          onVerticalDragUpdate: (d) => setState(() => _pan -= Offset(0, d.delta.dy / _zoom)),
          child: SizedBox(
            height: 240,
            width: double.infinity,
            child: CustomPaint(
              painter: _SeamPainter(
                _cols((aEnd - min(a.w, reach)) * q, aEnd * q),
                _cols(b.x * q, (b.x + min(b.w, reach)) * q),
                gap: _g,
                hd: _hd,
                cssPerSrc: _hd / src.height,
                zoom: _zoom,
                pan: _pan,
                bg: Colors.white,
                mark: _mark,
                guides: _guides,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One seam as X draws it, in CSS px: left photo ends at x = 0, the gap, right photo starts at x = gap.
class _SeamPainter extends CustomPainter {
  _SeamPainter(
    this.left,
    this.right, {
    required this.gap,
    required this.hd,
    required this.cssPerSrc,
    required this.zoom,
    required this.pan,
    required this.bg,
    required this.mark,
    required this.guides,
  });

  final _Cols left, right;
  final double gap, hd, cssPerSrc; // gap and photo height in CSS px; CSS px per source px
  final int zoom;
  final Offset pan;
  final Color bg;
  final bool mark, guides;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawColor(bg, BlendMode.src)
      ..translate(size.width / 2, size.height / 2)
      ..scale(zoom.toDouble())
      ..translate(-gap / 2 - pan.dx, -hd / 2 - pan.dy);
    final lw = (left.to - left.from) * cssPerSrc, rw = (right.to - right.from) * cssPerSrc;
    const r = Radius.circular(_xRadius);
    _photo(canvas, left, RRect.fromLTRBAndCorners(-lw, 0, 0, hd, topRight: r, bottomRight: r));
    _photo(canvas, right, RRect.fromLTRBAndCorners(gap, 0, gap + rw, hd, topLeft: r, bottomLeft: r));
    if (mark) canvas.drawRect(Rect.fromLTRB(0, 0, gap, hd), Paint()..color = const Color(0xCCFF1744));
    if (guides) {
      final p = Paint()..color = const Color(0x8000B8D4); // strokeWidth 0: hairline at any zoom
      for (var y = 0.0; y <= hd; y += 20) {
        canvas.drawLine(Offset(-lw, y), Offset(gap + rw, y), p);
      }
      p.color = const Color(0xFFFFD600);
      canvas
        ..drawLine(Offset.zero, Offset(0, hd), p)
        ..drawLine(Offset(gap, 0), Offset(gap, hd), p);
    }
  }

  void _photo(Canvas canvas, _Cols c, RRect dst) {
    final i = c.image;
    if (i == null) return; // still decoding
    final k = i.width / (c.last - c.first);
    canvas
      ..save()
      ..clipRRect(dst)
      ..drawImageRect(
        i,
        Rect.fromLTRB((c.from - c.first) * k, 0, (c.to - c.first) * k, i.height.toDouble()),
        dst.outerRect,
        // True pixels when zoomed in, so a 1 px misalignment is visible.
        Paint()..filterQuality = zoom >= 4 ? FilterQuality.none : FilterQuality.medium,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_SeamPainter old) => true;
}
