import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> downloadBytes(Uint8List bytes, String name) async {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
  web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..click();
  // Revoke later; revoking right after click can cancel the download in some browsers.
  Future.delayed(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
}

final _nav = web.window.navigator;

/// Touch device with file sharing: offer the share sheet (WhatsApp, X, Photos...).
bool get preferShare => web.window.matchMedia('(pointer: coarse)').matches && _nav.has('canShare');

/// iOS browsers (all WebKit) block back-to-back downloads, so there the share sheet replaces them
/// ("Save N Images" to Photos). A touch "Macintosh" is an iPad in desktop mode.
bool get isIOS => preferShare && RegExp('iPhone|iPad|iPod|Macintosh').hasMatch(_nav.userAgent);

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

/// Splits [files] into shares Chrome accepts: at most 10 files and 50 MB each (navigator_share.cc),
/// else it refuses the whole share. WebKit (iOS) has no such limit: one batch there.
List<Map<String, Uint8List>> shareBatches(Map<String, Uint8List> files) {
  if (isIOS) return [files];
  final batches = <Map<String, Uint8List>>[];
  var bytes = 0;
  for (final MapEntry(key: name, value: data) in files.entries) {
    if (batches.isEmpty || batches.last.length == 10 || bytes + data.length > 50 << 20) {
      batches.add({});
      bytes = 0;
    }
    batches.last[name] = data;
    bytes += data.length;
  }
  return batches;
}

String _mime(String name) => switch (name.split('.').last) {
  'jpg' => 'image/jpeg',
  'tif' => 'image/tiff',
  final ext => 'image/$ext',
};
