import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_divider/split.dart';

void main() {
  test('uneven split loses no pixels', () {
    final p = computePieces(width: 10, height: 5, rows: 1, cols: 3);
    expect(p.map((e) => (e.x, e.w)), [(0, 3), (3, 4), (7, 3)]);
    expect(p.every((e) => e.y == 0 && e.h == 5), isTrue);
  });

  test('gap: floor before the cut, ceil after, outer edges untouched', () {
    final p = computePieces(width: 10, height: 10, rows: 2, cols: 2, gapX: 3, gapY: 2);
    expect(p.map((e) => (e.row, e.col, e.x, e.y, e.w, e.h)), [
      (1, 1, 0, 0, 4, 4),
      (1, 2, 7, 0, 3, 4),
      (2, 1, 0, 6, 4, 4),
      (2, 2, 7, 6, 3, 4),
    ]);
  });

  test('rejects pieces smaller than 1px', () {
    expect(() => computePieces(width: 3, height: 1, rows: 1, cols: 3, gapX: 2), throwsArgumentError);
    expect(() => computePieces(width: 2, height: 1, rows: 1, cols: 3), throwsArgumentError);
    expect(() => computePieces(width: 2, height: 1, rows: 0, cols: 1), throwsArgumentError);
  });

  test('same-as-input falls back to png for webp', () {
    expect(outExt(OutFormat.same, img.ImageFormat.webp), 'png');
    expect(outExt(OutFormat.same, img.ImageFormat.jpg), 'jpg');
  });

  group('X gap compensation', () {
    test('1200 px tall output skips ~9.09 px; scales with height and gap', () {
      final g = xSourceGap(cssGap: 5.33, cssHeight: 703.85, imageHeight: 1200);
      expect(g, closeTo(9.087, 0.001));
      expect(xSourceGap(cssGap: 5.33, cssHeight: 703.85, imageHeight: 1600), closeTo(12.116, 0.001));
      expect(xSourceGap(cssGap: 5.33, cssHeight: 703.85, imageHeight: 600), closeTo(g / 2, 1e-9));
      expect(xSourceGap(cssGap: 6, cssHeight: 703.85, imageHeight: 1200), closeTo(10.229, 0.001));
      expect(() => xSourceGap(cssGap: 5.33, cssHeight: 0, imageHeight: 1200), throwsArgumentError);
      expect(() => xSourceGap(cssGap: -1, cssHeight: 703.85, imageHeight: 1200), throwsArgumentError);
    });

    test('gap 0 is the plain equal split', () {
      final plain = computePieces(width: 1000, height: 50, rows: 1, cols: 7);
      expect(xPieces(width: 1000, height: 50, n: 7, gap: 0).map((p) => (p.x, p.w)), plain.map((p) => (p.x, p.w)));
    });

    test('3000x1200 in 3: one ~9 px strip per seam, equal widths, outer edges kept', () {
      final p = xPieces(width: 3000, height: 1200, n: 3, gap: 9.087);
      expect(p.map((e) => (e.x, e.w)), [(0, 994), (1003, 994), (2006, 994)]);
      expect(p.every((e) => e.y == 0 && e.h == 1200), isTrue);
    });

    test('20 photos: where X draws each photo matches its source columns within 0.5 px', () {
      const w = 6000, h = 1200, n = 20, cssGap = 5.33, cssH = 703.85;
      final gap = xSourceGap(cssGap: cssGap, cssHeight: cssH, imageHeight: h);
      // X's position of photo i (CSS px from the first photo), mapped back to source px.
      List<double> shown(List<Piece> p) {
        final out = <double>[];
        var left = 0.0;
        for (final e in p) {
          out.add(left * h / cssH);
          left += xDisplayWidth(e, cssH) + cssGap;
        }
        return out;
      }

      final p = xPieces(width: w, height: h, n: n, gap: gap);
      expect(p.first.x, 0);
      expect(p.last.x + p.last.w, w);
      expect(p.map((e) => e.w).toSet().length, lessThanOrEqualTo(2)); // equal within 1 px
      for (var i = 1; i < n; i++) {
        expect(p[i].x - p[i - 1].x - p[i - 1].w, anyOf(9, 10), reason: 'seam $i');
      }
      final pos = shown(p);
      for (var i = 0; i < n; i++) {
        expect(pos[i] - p[i].x, closeTo(0, 0.5 + 1e-9), reason: 'photo ${i + 1}');
      }
      // Without compensation the jump grows by ~9 px per seam: ~173 px off at photo 20.
      final plain = computePieces(width: w, height: h, rows: 1, cols: n);
      expect(shown(plain).last - plain.last.x, closeTo(19 * gap, 1));
    });

    test('rejects gaps that leave no room', () {
      expect(() => xPieces(width: 30, height: 10, n: 3, gap: 14), throwsArgumentError);
      expect(() => xPieces(width: 30, height: 10, n: 3, gap: -1), throwsArgumentError);
      expect(() => xPieces(width: 30, height: 10, n: 0, gap: 1), throwsArgumentError);
    });
  });

  test('encoded piece has the cropped size', () {
    final src = img.Image(width: 10, height: 4);
    final p = computePieces(width: 10, height: 4, rows: 1, cols: 3)[1];
    expect(img.decodePng(encodePiece(src, p, 'png', 100))!.width, 4);
  });
}
