import Cocoa
import FlutterMacOS
import Vision

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  static var ocrChannel: FlutterMethodChannel?

  static func registerOcrChannel(with controller: FlutterViewController) {
    guard ocrChannel == nil else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "versecatch/ocr",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      if call.method == "recognizeTextFromPath" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "invalid_argument", message: "Expected a path argument", details: nil))
          return
        }
        recognizeText(from: path, completion: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    ocrChannel = channel
  }

  private static func recognizeText(from path: String, completion: @escaping FlutterResult) {
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
    request.recognitionLanguages = ["en-US"]

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
