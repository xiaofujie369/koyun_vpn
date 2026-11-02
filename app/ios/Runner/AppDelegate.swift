import Flutter
import NetworkExtension
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
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "KoyunCore") {
      KoyunCore.shared.register(messenger: r.messenger())
    }
  }
}

/// Flutter <-> NetworkExtension 桥（与 Android 的 MethodChannel 协议一致）
final class KoyunCore: NSObject, FlutterStreamHandler {
  static let shared = KoyunCore()
  private var manager: NETunnelProviderManager?
  private var sink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "koyun/core", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    FlutterEventChannel(name: "koyun/core/events", binaryMessenger: messenger).setStreamHandler(self)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "sharedDir":
      result(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KoyunShared.appGroup)?.path)
    case "prepare":
      loadManager { m, err in result(m != nil && err == nil) }
    case "status":
      loadManager { m, _ in result(Self.statusString(m?.connection.status ?? .invalid)) }
    case "start":
      guard let args = call.arguments as? [String: Any], let config = args["config"] as? String else {
        return result(FlutterError(code: "bad_config", message: "empty config", details: nil))
      }
      loadManager { m, err in
        guard let m else { return result(FlutterError(code: "prepare", message: err?.localizedDescription, details: nil)) }
        // 已连接：发消息让扩展热重载，不断线
        if m.connection.status == .connected, let s = m.connection as? NETunnelProviderSession {
          try? s.sendProviderMessage(config.data(using: .utf8)!) { _ in }
          return result(nil)
        }
        do {
          try m.connection.startVPNTunnel(options: ["configContent": config as NSString])
          result(nil)
        } catch {
          result(FlutterError(code: "start", message: error.localizedDescription, details: nil))
        }
      }
    case "stop":
      manager?.connection.stopVPNTunnel()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 读取或创建 VPN 配置（首次会弹出系统"添加 VPN 配置"授权）
  private func loadManager(_ done: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { list, err in
      if let err { return DispatchQueue.main.async { done(nil, err) } }
      let m = list?.first ?? NETunnelProviderManager()
      let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
      proto.providerBundleIdentifier = KoyunShared.extensionBundleId
      proto.serverAddress = "Koyun"
      m.protocolConfiguration = proto
      m.localizedDescription = "Koyun"
      m.isEnabled = true
      m.saveToPreferences { err in
        if let err { return DispatchQueue.main.async { done(nil, err) } }
        m.loadFromPreferences { err in
          DispatchQueue.main.async {
            self.manager = m
            self.observe(m)
            done(err == nil ? m : nil, err)
          }
        }
      }
    }
  }

  private func observe(_ m: NETunnelProviderManager) {
    if observer != nil { return }
    observer = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange, object: m.connection, queue: .main
    ) { [weak self] _ in
      self?.sink?(["status": Self.statusString(m.connection.status)])
    }
  }

  static func statusString(_ s: NEVPNStatus) -> String {
    switch s {
    case .connected: return "running"
    case .connecting, .reasserting: return "starting"
    default: return "stopped"
    }
  }

  func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    if let m = manager { events(["status": Self.statusString(m.connection.status)]) }
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
