import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

extension type _Options._(JSObject _) implements JSObject {
  external factory _Options({web.Blob blob, String toType});
}

@JS('heic2any')
external JSPromise<web.Blob> _heic2any(_Options options);

/// HEIC/HEIF box header: 'ftyp' at byte 4 (also matches AVIF/MP4; heic2any rejects those).
bool looksLikeHeic(Uint8List b) => b.length > 12 && String.fromCharCodes(b, 4, 8) == 'ftyp';

/// HEIC -> PNG bytes via heic2any (web/index.html). Null if it can't be converted or the script didn't load.
Future<Uint8List?> heicToPng(Uint8List bytes) async {
  try {
    final png = await _heic2any(_Options(blob: web.Blob([bytes.toJS].toJS), toType: 'image/png')).toDart;
    return (await png.arrayBuffer().toDart).toDart.asUint8List();
  } catch (_) {
    return null;
  }
}
