import Flutter
import UIKit
import ImageIO
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var ocrChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerOcrChannel(with: engineBridge.pluginRegistry.registrar(forPlugin: "VerseCatchOcrPlugin"))
  }

  private func registerOcrChannel(with registrar: FlutterPluginRegistrar?) {
    guard let registrar else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "versecatch/ocr",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "ocr_handler_unavailable",
            message: "OCR handler is unavailable",
            details: nil
          )
        )
        return
      }

      guard call.method == "recognizeTextFromPath" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(
          FlutterError(
            code: "invalid_argument",
            message: "Expected a path argument",
            details: nil
          )
        )
        return
      }

      self.recognizeText(from: path, completion: result)
    }
    ocrChannel = channel
  }

  private func recognizeText(from path: String, completion: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
      completion(
        FlutterError(
          code: "image_load_failed",
          message: "Unable to load image for OCR",
          details: ["path": path]
        )
      )
      return
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["es-MX", "es-ES", "en-US"]

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      completion(
        FlutterError(
          code: "ocr_failed",
          message: error.localizedDescription,
          details: ["path": path]
        )
      )
      return
    }

    let recognizedText = request.results?
      .compactMap { observation in
        observation.topCandidates(1).first?.string
      }
      .joined(separator: "\n") ?? ""

    completion(recognizedText)
  }
}
