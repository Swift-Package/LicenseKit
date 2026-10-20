#!/bin/bash
set -e

SCHEME="LicenseKit"
CONFIGURATION="Release"
BUILD_DIR="./build"
OUTPUT="./build/LicenseKit.xcframework"

echo "清理之前的构建..."
rm -rf "${BUILD_DIR}" "${OUTPUT}"

echo "真机框架打包中..."
xcodebuild archive \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphoneos \
  -archivePath "${BUILD_DIR}/ios_devices.xcarchive" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "模拟器框架打包中..."
xcodebuild archive \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphonesimulator \
  -archivePath "${BUILD_DIR}/ios_sim.xcarchive" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "合并 XCFramework..."
# LicenseKit 通过 @_implementationOnly + 静态链接并入 GodoxXKit.framework，产物保持单 framework
xcodebuild -create-xcframework \
  -framework "${BUILD_DIR}/ios_devices.xcarchive/Products/Library/Frameworks/LicenseKit.framework" \
  -framework "${BUILD_DIR}/ios_sim.xcarchive/Products/Library/Frameworks/LicenseKit.framework" \
  -output "${OUTPUT}"

echo "构建完成: ${OUTPUT}"
