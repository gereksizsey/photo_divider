package com.example.photo_divider

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // HEIC -> PNG for lib/native.dart's heicToPng: Dart's image package can't read HEIC, Android 9+ can.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "heic").setMethodCallHandler { call, result ->
            val heic = call.arguments as ByteArray
            Thread { // a big photo takes seconds to decode and encode; keep the UI thread free
                val png = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) null else try {
                    // ImageDecoder applies the photo's rotation (BitmapFactory doesn't); software so compress can read it.
                    val bmp = ImageDecoder.decodeBitmap(ImageDecoder.createSource(ByteBuffer.wrap(heic))) { d, _, _ ->
                        d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    }
                    ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
                } catch (e: Throwable) { // not HEIC after all, or too big for memory: Dart shows its message
                    null
                }
                Handler(Looper.getMainLooper()).post { result.success(png) }
            }.start()
        }
    }
}
