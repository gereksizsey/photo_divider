import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void downloadBytes(Uint8List bytes, String name) {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
  web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..click();
  // Revoke later; revoking right after click can cancel the download in some browsers.
  Future.delayed(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
}
