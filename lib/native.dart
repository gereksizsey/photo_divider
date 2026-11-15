// Android app versions of the web-only download.dart, drop.dart and heic.dart; main.dart picks per platform.
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// Saves to the phone's gallery.
Future<void> downloadBytes(Uint8List bytes, String name) async {
  if (!await Gal.hasPermission()) await Gal.requestPermission(); // only Android 10 and older ask
  await Gal.putImageBytes(bytes, name: name.substring(0, name.lastIndexOf('.'))); // gal adds the extension
}

// Android's own share sheet: always there, no tap expiry, no file count limit.
bool get preferShare => true;
bool get isIOS => false;
bool get tapStillActive => true;

Future<bool> shareFiles(Map<String, Uint8List> files) async {
  await SharePlus.instance.share(
    ShareParams(files: [for (final MapEntry(key: name, value: bytes) in files.entries) XFile.fromData(bytes, name: name)]),
  );
  return true;
}

List<Map<String, Uint8List>> shareBatches(Map<String, Uint8List> files) => [files];

/// No drag-and-drop or paste in the app: photos come from the picker.
void onDropOrPaste(void Function(String name, Future<Uint8List> Function() read) onFile) {}

/// HEIC -> PNG bytes via Android's decoder (MainActivity.kt). Null if it can't, e.g. before Android 9.
Future<Uint8List?> heicToPng(Uint8List bytes) async {
  try {
    return await const MethodChannel('heic').invokeMethod<Uint8List>('toPng', bytes);
  } on PlatformException {
    return null;
  }
}
