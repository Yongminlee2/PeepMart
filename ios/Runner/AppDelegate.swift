import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MoreGamesStore") {
      MoreGamesStore.register(messenger: registrar.messenger())
    }
    #if DEBUG
      if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DebugArgs") {
        DebugArgs.register(messenger: registrar.messenger())
      }
    #endif
  }
}

/// 다른 게임의 받기. 안드로이드는 같은 이름의 채널(`app/store`)로 플레이 스토어를 연다.
/// 아이폰은 앱스토어 주소만 연다 — 다른 플랫폼 스토어로 보내면 심사 지침 2.3.10.
enum MoreGamesStore {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app/store", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "openUrl",
        let text = call.arguments as? String,
        let url = URL(string: text),
        url.scheme == "https", url.host == "apps.apple.com"
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      UIApplication.shared.open(url)
      result(nil)
    }
  }
}

/// 화면 아래에서 끌어 걷는 게임이라 홈 제스처를 한 번 늦춘다 — 첫 쓸기는 게임이 받고
/// 홈 바만 나타난다. 정말 나가려면 한 번 더 쓸면 된다. 홈 바도 평소엔 숨긴다.
/// Main.storyboard 의 viewController 가 이 클래스다.
class GameViewController: FlutterViewController {
  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
  override var prefersHomeIndicatorAutoHidden: Bool { true }
}

#if DEBUG
  /// 시뮬레이터 화면 확인용(디버그 빌드만): 실행 인자를 Dart 에 넘긴다.
  /// `xcrun simctl launch <기기> com.peep.mart -shot game` → lib/ui/debug_shot.dart
  enum DebugArgs {
    static func register(messenger: FlutterBinaryMessenger) {
      let channel = FlutterMethodChannel(name: "peep/debug", binaryMessenger: messenger)
      channel.setMethodCallHandler { call, result in
        result(call.method == "args" ? ProcessInfo.processInfo.arguments : FlutterMethodNotImplemented)
      }
    }
  }
#endif
