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
    .library(name: "WebKitUIMCPLicensing", targets: ["WebKitUIMCPLicensing"]),
    .executable(name: "webkitui-mcp", targets: ["WebKitUIMCPCLI"]),
    .executable(name: "webkitui-mcp-confirm", targets: ["WebKitUIMCPConfirm"]),
    .executable(name: "webkitui-mcp-aqua-broker", targets: ["WebKitUIMCPAquaBroker"]),
    .executable(name: "webkitui-mcp-relay", targets: ["WebKitUIMCPRelay"]),
    .executable(name: "wkjs-handle-probe", targets: ["WKJSHandleProbe"]),
    .executable(name: "webkitui-benchmark", targets: ["WebKitUIMCPBenchmark"]),
    .executable(
      name: "credential-broker-physical-validation",
      targets: ["CredentialBrokerPhysicalValidation"]
    ),
  ],
  targets: [
    .systemLibrary(name: "CLaunchShim"),
    .target(name: "WebKitUIMCPCore"),
    .target(
      name: "WebKitUIMCPLicensing",
      resources: [.process("Resources")]
    ),
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
      dependencies: ["WebKitUIMCPLicensing", "WebKitUIMCPRuntime", "WebKitUIMCPServer"]
    ),
    .executableTarget(name: "WebKitUIMCPConfirm"),
    .executableTarget(
      name: "WebKitUIMCPAquaBroker",
      dependencies: [
        "CLaunchShim", "WebKitUIMCPLicensing", "WebKitUIMCPRuntime", "WebKitUIMCPServer",
      ]
    ),
    .executableTarget(name: "WebKitUIMCPRelay"),
    .executableTarget(name: "WKJSHandleProbe"),
    .executableTarget(
      name: "WebKitUIMCPBenchmark",
      dependencies: ["WebKitUIMCPRuntime"]
    ),
    .executableTarget(
      name: "CredentialBrokerPhysicalValidation",
      dependencies: ["WebKitUIMCPRuntime", "WebKitUIMCPServer"]
    ),
    .testTarget(
      name: "WebKitUIMCPCoreTests",
      dependencies: ["WebKitUIMCPCore"]
    ),
    .testTarget(
      name: "WebKitUIMCPLicensingTests",
      dependencies: ["WebKitUIMCPLicensing"]
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
