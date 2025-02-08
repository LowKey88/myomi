package com.friend.ios

import android.content.Intent
import androidx.annotation.NonNull
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import com.friend.ios.cpp.Cpp

class MainActivity: FlutterActivity() {
    private val NOTIFICATION_CHANNEL = "com.friend.ios/notifyOnKill"
    private val LC3_CHANNEL = "com.friend.ios/channel"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize LC3 decoder
        Cpp.init()
        
        // Register plugins
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Notification channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setMethodCallHandler { call, result ->
            if(call.method == "setNotificationOnKillService") {
                val title = call.argument<String>("title")
                val description = call.argument<String>("description")

                val serviceIntent = Intent(this, NotificationOnKillService::class.java)
                serviceIntent.putExtra("title", title)
                serviceIntent.putExtra("description", description)

                startService(serviceIntent)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        // LC3 decode channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LC3_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "decodeLC3") {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    val decodedData = Cpp.decodeLC3(data)
                    result.success(decodedData)
                } else {
                    result.error("INVALID_ARGUMENT", "Data is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}