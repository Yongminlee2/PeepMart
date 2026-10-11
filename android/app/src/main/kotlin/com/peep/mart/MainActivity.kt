package com.peep.mart

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 「개발자의 다른 게임」: 플레이 스토어를 정해서 연다. url_launcher 로 market:// 을 열면
    // 삼성 폰은 갤럭시 스토어까지 받아서 "어느 앱으로 열까요" 창이 먼저 뜬다.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/store")
            .setMethodCallHandler { call, result ->
                val q = call.arguments as? String
                if (call.method != "open" || q == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://$q")).setPackage("com.android.vending"))
                } catch (e: ActivityNotFoundException) {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/$q")))
                }
                result.success(null)
            }
    }
}
