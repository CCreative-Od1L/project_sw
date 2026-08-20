import Flutter
import LocalAuthentication
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "project_sw/biometric_key_store"
  private let keychainService = "com.ccreativeod1l.projectSw.biometric"
  private let keychainAccount = "k_bio"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      let context = LAContext()
      var error: NSError?
      let available = context.canEvaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        error: &error
      )
      result(available)
    case "createKey":
      createKey(result: result)
    case "loadKey":
      loadKey(result: result)
    case "deleteKey":
      deleteKey(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func createKey(result: @escaping FlutterResult) {
    guard isBiometricAvailable() else {
      result(flutterError("unavailable"))
      return
    }
    deleteKeychainItem()
    var bytes = [UInt8](repeating: 0, count: 32)
    let byteCount = bytes.count
    defer { bytes = [UInt8](repeating: 0, count: byteCount) }
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      result(flutterError("authentication_failed"))
      return
    }
    let data = Data(bytes)
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      .biometryCurrentSet,
      nil
    ) else {
      result(flutterError("authentication_failed"))
      return
    }
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: keychainService,
      kSecAttrAccount: keychainAccount,
      kSecAttrAccessControl: access,
      kSecValueData: data,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecSuccess {
      result(FlutterStandardTypedData(bytes: data))
    } else {
      result(flutterError(normalizedError(status)))
    }
  }

  private func loadKey(result: @escaping FlutterResult) {
    let context = LAContext()
    context.localizedCancelTitle = "Use master password"
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: keychainService,
      kSecAttrAccount: keychainAccount,
      kSecReturnData: true,
      kSecUseAuthenticationContext: context,
      kSecUseOperationPrompt: "Use biometrics to unlock your password vault",
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
      result(flutterError(normalizedError(status)))
      return
    }
    result(FlutterStandardTypedData(bytes: data))
  }

  private func deleteKey(result: @escaping FlutterResult) {
    let status = deleteKeychainItem()
    if status == errSecSuccess || status == errSecItemNotFound {
      result(nil)
    } else {
      result(flutterError("authentication_failed"))
    }
  }

  @discardableResult
  private func deleteKeychainItem() -> OSStatus {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: keychainService,
      kSecAttrAccount: keychainAccount,
    ]
    return SecItemDelete(query as CFDictionary)
  }

  private func isBiometricAvailable() -> Bool {
    let context = LAContext()
    var error: NSError?
    return context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      error: &error
    )
  }

  private func normalizedError(_ status: OSStatus) -> String {
    switch status {
    case errSecItemNotFound:
      return "unavailable"
    case errSecUserCanceled, errSecInteractionNotAllowed:
      return "cancelled"
    case errSecAuthFailed:
      return "authentication_failed"
    default:
      return "authentication_failed"
    }
  }

  private func flutterError(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }
}
