@TestOn('browser') // download.dart uses package:web; run with: flutter test --platform chrome
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_divider/download.dart';

void main() {
  test('share batches: max 10 files and 50 MB each, order kept', () {
    final files = {for (var i = 0; i < 23; i++) 'p$i.png': Uint8List(1)};
    expect(shareBatches(files).map((b) => b.length), [10, 10, 3]);
    expect(shareBatches(files).expand((b) => b.keys), files.keys);

    final big = {'a': Uint8List(30 << 20), 'b': Uint8List(30 << 20), 'c': Uint8List(60 << 20), 'd': Uint8List(1)};
    expect(shareBatches(big).map((b) => b.keys.join()), ['a', 'b', 'c', 'd']);
  });
}
