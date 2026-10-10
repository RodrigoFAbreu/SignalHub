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
    registerShareChannel(engineBridge.pluginRegistry)
  }

  // The share sheet of a key shown once (lib/src/ui/text_sharer.dart).
  private func registerShareChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "SignalHubShare") else { return }
    let channel = FlutterMethodChannel(
      name: "io.github.rodrigofabreu.signalhub/share",
      binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "text", let text = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let root = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController
      guard let presenter = root else {
        result(false)
        return
      }
      let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
      // An iPad shows the sheet as a popover, which needs somewhere to point.
      sheet.popoverPresentationController?.sourceView = presenter.view
      sheet.popoverPresentationController?.sourceRect = CGRect(
        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
      sheet.popoverPresentationController?.permittedArrowDirections = []
      presenter.present(sheet, animated: true) { result(true) }
    }
  }
}
