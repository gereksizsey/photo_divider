import 'dart:typed_data';

import 'package:image/image.dart' as img;

class Piece {
  final int row, col, x, y, w, h;
  const Piece(this.row, this.col, this.x, this.y, this.w, this.h);
}

/// One axis: [start, end) spans for [n] pieces over [size] px, gap removed only at inner cuts.
List<(int, int)> _spans(int size, int n, int gap) => [
  for (var i = 0; i < n; i++)
    (
      (i * size / n).round() + (i > 0 ? (gap + 1) ~/ 2 : 0),
      ((i + 1) * size / n).round() - (i < n - 1 ? gap ~/ 2 : 0),
    ),
];

/// Pieces left-to-right, top-to-bottom. Throws [ArgumentError] if any piece would be < 1x1 px.
List<Piece> computePieces({
  required int width,
  required int height,
  required int rows,
  required int cols,
  int gapX = 0,
  int gapY = 0,
}) {
  if (rows < 1 || cols < 1) throw ArgumentError('Count must be at least 1');
  if (gapX < 0 || gapY < 0) throw ArgumentError('Gap cannot be negative');
  final xs = _spans(width, cols, gapX), ys = _spans(height, rows, gapY);
  if ([...xs, ...ys].any((s) => s.$2 - s.$1 < 1)) {
    throw ArgumentError('Too many pieces or gap too large for a ${width}x$height image');
  }
  return [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++)
        Piece(r + 1, c + 1, xs[c].$1, ys[r].$1, xs[c].$2 - xs[c].$1, ys[r].$2 - ys[r].$1),
  ];
}

/// X/Twitter gallery gap in image px: the CSS gap times how many image px one CSS px covers when
/// the photo is shown [cssHeight] CSS px tall. The one formula the X export and the X preview share.
double xSourceGap({required double cssGap, required double cssHeight, required int imageHeight}) {
  if (!(cssHeight > 0) || !(cssGap >= 0 && cssGap.isFinite)) {
    throw ArgumentError('Twitter gap must be ≥ 0 and display height > 0');
  }
  return cssGap * imageHeight / cssHeight;
}

/// 1 row x [n] equal-width pieces for an X gallery: [gap] image px are skipped at each inner seam,
/// because X covers that much of the panorama with its gap. Skipped total (round(i * gap)) and widths
/// are both rounded cumulatively, so piece i sits within 0.5 px of its ideal spot even after 20 photos.
/// Outer edges are kept. Throws [ArgumentError] if a piece would be < 1 px wide.
List<Piece> xPieces({required int width, required int height, required int n, required double gap}) {
  if (n < 1) throw ArgumentError('Count must be at least 1');
  if (!(gap >= 0 && gap < width)) throw ArgumentError('Gap must be between 0 and the image width');
  final visible = width - ((n - 1) * gap).round();
  if (visible < n) throw ArgumentError('Too many pieces or gap too large for a ${width}x$height image');
  int edge(int i) => (i * visible / n).round();
  return [
    for (var i = 0; i < n; i++) Piece(1, i + 1, edge(i) + (i * gap).round(), 0, edge(i + 1) - edge(i), height),
  ];
}

/// Width in CSS px that X shows [p] at: every photo is [cssHeight] tall, aspect ratio kept.
double xDisplayWidth(Piece p, double cssHeight) => p.w * cssHeight / p.h;

enum OutFormat { same, jpg, png }

/// HEIC/WebP etc. can't be encoded in the browser, so "same" falls back to PNG.
String outExt(OutFormat out, img.ImageFormat? input) => switch (out) {
  OutFormat.jpg => 'jpg',
  OutFormat.png => 'png',
  OutFormat.same => switch (input) {
    img.ImageFormat.jpg => 'jpg',
    img.ImageFormat.gif => 'gif',
    img.ImageFormat.bmp => 'bmp',
    img.ImageFormat.tiff => 'tif',
    _ => 'png',
  },
};

/// HEIC/HEIF box header: 'ftyp' at byte 4 (also matches AVIF/MP4; the HEIC converters reject those).
bool looksLikeHeic(Uint8List b) => b.length > 12 && String.fromCharCodes(b, 4, 8) == 'ftyp';

Uint8List encodePiece(img.Image src, Piece p, String ext, int quality) {
  final c = img.copyCrop(src, x: p.x, y: p.y, width: p.w, height: p.h);
  // copyCrop keeps the source EXIF: its capture date files pieces under the original in galleries,
  // and it also carries the original's thumbnail and GPS.
  c.exif.clear();
  return switch (ext) {
    'jpg' => img.encodeJpg(c, quality: quality),
    'gif' => img.encodeGif(c),
    'bmp' => img.encodeBmp(c),
    'tif' => img.encodeTiff(c),
    _ => img.encodePng(c),
  };
}
