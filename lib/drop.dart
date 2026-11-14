import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Calls [onFile] with the first file dropped anywhere on the page or pasted with Ctrl+V.
void onDropOrPaste(void Function(String name, Future<Uint8List> Function() read) onFile) {
  void take(web.FileList? files) {
    final f = files?.item(0);
    if (f != null) onFile(f.name, () async => (await f.arrayBuffer().toDart).toDart.asUint8List());
  }

  web.document
    // Without this the browser refuses the drop, or opens the file in place of the app.
    ..addEventListener('dragover', ((web.DragEvent e) => e.preventDefault()).toJS)
    ..addEventListener(
      'drop',
      ((web.DragEvent e) {
        e.preventDefault();
        take(e.dataTransfer?.files);
      }).toJS,
    )
    ..addEventListener(
      'paste',
      ((web.ClipboardEvent e) {
        // Pasting into a number field isn't for us, even if the clipboard also holds a picture (Excel does that).
        if (const ['INPUT', 'TEXTAREA'].contains(web.document.activeElement?.tagName)) return;
        take(e.clipboardData?.files);
      }).toJS,
    );
}
