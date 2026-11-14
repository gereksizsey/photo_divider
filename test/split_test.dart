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

  test('encoded piece has the cropped size', () {
    final src = img.Image(width: 10, height: 4);
    final p = computePieces(width: 10, height: 4, rows: 1, cols: 3)[1];
    expect(img.decodePng(encodePiece(src, p, 'png', 100))!.width, 4);
  });
}
