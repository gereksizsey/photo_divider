import 'dart:js_interop';
import 'dart:js_interop_unsafe';
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

final _nav = web.window.navigator;

/// Touch device with file sharing. iOS Safari blocks back-to-back downloads, but its share sheet
/// can "Save N Images" to Photos in one go.
bool get preferShare => web.window.matchMedia('(pointer: coarse)').matches && _nav.has('canShare');

/// navigator.share only works shortly after a tap; false once that has expired (e.g. after a slow encode).
bool get tapStillActive => !_nav.has('userActivation') || _nav.userActivation.isActive;

/// Opens the share sheet with all [files] (name -> bytes). False if the browser refuses them
/// (type, count or size limit); download them instead.
Future<bool> shareFiles(Map<String, Uint8List> files) async {
  final data = web.ShareData(
    files: [
      for (final MapEntry(key: name, value: bytes) in files.entries)
        web.File([bytes.toJS].toJS, name, web.FilePropertyBag(type: _mime(name))),
    ].toJS,
  );
  if (!_nav.canShare(data)) return false;
  try {
    await _nav.share(data).toDart;
  } catch (e) {
    final name = (e as web.DOMException).name;
    if (name == 'NotAllowedError') return false; // Chrome's file count/size limit
    if (name != 'AbortError') rethrow; // AbortError: the user closed the sheet
  }
  return true;
}

String _mime(String name) => switch (name.split('.').last) {
  'jpg' => 'image/jpeg',
  'tif' => 'image/tiff',
  final ext => 'image/$ext',
};
