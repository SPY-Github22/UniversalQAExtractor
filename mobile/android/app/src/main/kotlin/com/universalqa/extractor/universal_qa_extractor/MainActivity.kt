package com.universalqa.extractor.universal_qa_extractor

import android.content.Intent
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.universalqaextractor.mobile/screen_capture"
    private var isServiceRunning = false

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCapture" -> {
                    val serviceIntent = Intent(this, MediaProjectionService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    isServiceRunning = true
                    result.success(true)
                }
                "stopCapture" -> {
                    val serviceIntent = Intent(this, MediaProjectionService::class.java)
                    stopService(serviceIntent)
                    isServiceRunning = false
                    result.success(true)
                }
                "isCapturing" -> {
                    result.success(isServiceRunning)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
