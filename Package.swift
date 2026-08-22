// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "WebKitUIMCP",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "WebKitUIMCPCore", targets: ["WebKitUIMCPCore"]),
    .library(name: "WebKitUIMCPRuntime", targets: ["WebKitUIMCPRuntime"]),
    .library(name: "WebKitUIMCPServer", targets: ["WebKitUIMCPServer"]),
    .executable(name: "webkitui-mcp", targets: ["WebKitUIMCPCLI"]),
    .executable(name: "wkjs-handle-probe", targets: ["WKJSHandleProbe"]),
    .executable(name: "webkitui-benchmark", targets: ["WebKitUIMCPBenchmark"]),
  ],
  targets: [
    .target(name: "WebKitUIMCPCore"),
    .target(
      name: "WebKitUIMCPRuntime",
      dependencies: ["WebKitUIMCPCore"]
    ),
    .target(
      name: "WebKitUIMCPServer",
      dependencies: ["WebKitUIMCPRuntime"]
    ),
    .executableTarget(
      name: "WebKitUIMCPCLI",
      dependencies: ["WebKitUIMCPServer"]
    ),
    .executableTarget(name: "WKJSHandleProbe"),
    .executableTarget(
      name: "WebKitUIMCPBenchmark",
      dependencies: ["WebKitUIMCPRuntime"]
    ),
    .testTarget(
      name: "WebKitUIMCPCoreTests",
      dependencies: ["WebKitUIMCPCore"]
    ),
    .testTarget(
      name: "WebKitUIMCPRuntimeTests",
      dependencies: ["WebKitUIMCPRuntime"]
    ),
    .testTarget(
      name: "WebKitUIMCPServerTests",
      dependencies: ["WebKitUIMCPServer"]
    ),
  ]
)
