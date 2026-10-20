// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "LicenseKit",
	platforms: [.iOS(.v15), .macOS(.v26), .visionOS(.v26)],
	products: [
		.library(name: "LicenseKit", targets: ["LicenseKit"]),
	],
	targets: [
		.target(name: "LicenseKit",
				path: "LicenseKit",
				exclude: ["LicenseKit.docc"],
				swiftSettings: [
					.enableUpcomingFeature("ApproachableConcurrency"),
				]),
		.testTarget(name: "LicenseKitTests",
					dependencies: ["LicenseKit"],
					path: "LicenseKitTests",
					swiftSettings: [
						.enableUpcomingFeature("ApproachableConcurrency"),
					]),
	],
	swiftLanguageModes: [.v5]
)
