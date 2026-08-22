import Foundation
import WebKit
import WebKitUIMCPRuntime

private struct Sample: Codable {
  let contextInitializationNanoseconds: UInt64
  let readinessNanoseconds: UInt64
  let observationNanoseconds: UInt64
  let captureNanoseconds: UInt64
  let observationBytes: Int
  let elementCount: Int
  let pngBytes: Int
  let pixelWidth: Int
  let pixelHeight: Int
}

private struct Result: Codable {
  let engine: String
  let mode: String
  let viewportPoints: [Int]
  let browserLaunchNanoseconds: UInt64?
  let samples: [Sample]
}

@main
struct WebKitUIMCPBenchmark {
  @MainActor
  static func main() async throws {
    guard CommandLine.arguments.count >= 2 else {
      FileHandle.standardError.write(
        Data("usage: webkitui-benchmark FIXTURE [ITERATIONS] [OUTPUT_JSON]\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
    let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let html = try String(contentsOf: fixtureURL, encoding: .utf8)
    let iterations = CommandLine.arguments.count >= 3 ? Int(CommandLine.arguments[2]) ?? 5 : 5
    guard iterations > 0, iterations <= 100 else {
      FileHandle.standardError.write(Data("iterations must be 1...100\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }

    var samples: [Sample] = []
    for _ in 0..<iterations {
      let initializationStart = DispatchTime.now().uptimeNanoseconds
      let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
      let initializationEnd = DispatchTime.now().uptimeNanoseconds

      let readinessStart = DispatchTime.now().uptimeNanoseconds
      _ = try await runtime.loadHTML(
        html,
        baseURL: URL(string: "https://benchmark.invalid/fixture"),
        timeout: .seconds(10),
        quietWindow: .milliseconds(300)
      )
      let readinessEnd = DispatchTime.now().uptimeNanoseconds

      let observationStart = DispatchTime.now().uptimeNanoseconds
      let observation = try await runtime.observe(maximumElements: 500)
      let observationEnd = DispatchTime.now().uptimeNanoseconds
      let observationData = try JSONEncoder().encode(observation)

      let captureStart = DispatchTime.now().uptimeNanoseconds
      let capture = try await runtime.capture()
      let captureEnd = DispatchTime.now().uptimeNanoseconds
      samples.append(
        Sample(
          contextInitializationNanoseconds: initializationEnd - initializationStart,
          readinessNanoseconds: readinessEnd - readinessStart,
          observationNanoseconds: observationEnd - observationStart,
          captureNanoseconds: captureEnd - captureStart,
          observationBytes: observationData.count,
          elementCount: observation.elements.count,
          pngBytes: capture.pngData.count,
          pixelWidth: capture.width,
          pixelHeight: capture.height
        ))
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(
      Result(
        engine: "WKWebView",
        mode: "offscreen-nonpersistent",
        viewportPoints: [1280, 800],
        browserLaunchNanoseconds: nil,
        samples: samples
      ))
    if CommandLine.arguments.count >= 4 {
      try data.write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
    } else {
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }
  }
}
