//
//  LicenseKitTests.swift
//  LicenseKitTests
//
//  Created by 杨俊艺 on 2026/10/20.
//

import Foundation
import Testing
import CryptoKit
@testable import LicenseKit

/// LicenseValidator 校验测试
struct LicenseValidatorTests {
	
	/// 每次测试生成全新临时密钥对
	private let privateKey = P256.Signing.PrivateKey()
	private static let testBundleId = "com.test.app"
	/// 过期时间到 2100-01-01
	private static let farFutureSeconds = UInt32(4_102_444_800)
	
	// MARK: - 测试内联签发
	private func sign(bundleId: String = testBundleId, exp: UInt32 = farFutureSeconds, version: UInt8 = 0x01, key: P256.Signing.PrivateKey? = nil) throws -> String {
		var data = Data([version])
		data.append(UInt8((exp >> 24) & 0xFF))
		data.append(UInt8((exp >> 16) & 0xFF))
		data.append(UInt8((exp >> 8) & 0xFF))
		data.append(UInt8(exp & 0xFF))
		let bundleIdBytes = Array(bundleId.utf8)
		data.append(UInt8(bundleIdBytes.count))
		data.append(contentsOf: bundleIdBytes)
		let signature = try (key ?? privateKey).signature(for: SHA256.hash(data: data))
		return LicenseBase64.encode(data + signature.rawRepresentation)
	}
	
	// MARK: - 生成公钥验证器
	private func makeValidator(bundleId: String = testBundleId) throws -> LicenseValidator {
		try LicenseValidator(publicKey: privateKey.publicKey.x963Representation, bundleId: bundleId)
	}
	
	// MARK: - 签发并校验往返
	@Test("合法许可证校验通过")
	func validLicenseRoundTrip() throws {
		let licenseString = try sign()
		let result = try makeValidator().validate(licenseString)
		let parsed = try #require(try? result.get())
		#expect(parsed.bundleId == Self.testBundleId)
		#expect(parsed.expiresAt == Date(timeIntervalSince1970: TimeInterval(Self.farFutureSeconds)))
	}
	
	@Test("许可证为紧凑单段格式")
	func licenseIsCompact() throws {
		let licenseString = try sign(bundleId: "com.godox.demo")
		// 6(头部)+14(bundleId)+64(签名)=84 字节 → base64url 112 字符
		#expect(licenseString.count == 112)
		#expect(!licenseString.contains("."))
	}
	
	@Test("payload 被篡改不通过")
	func tamperedPayloadRejected() throws {
		// 翻转 bundleId 区一个字节：结构仍合法但签名不再匹配
		let licenseString = try sign()
		var data = try #require(LicenseBase64.decode(licenseString))
		data[6] ^= 0x01
		let forged = LicenseBase64.encode(data)
		let result = try makeValidator().validate(forged)
		#expect(result == .failure(.signatureInvalid))
	}
	
	@Test("签名被篡改不通过")
	func tamperedSignatureRejected() throws {
		let licenseString = try sign()
		var data = try #require(LicenseBase64.decode(licenseString))
		data[data.count - 1] ^= 0x01
		let forged = LicenseBase64.encode(data)
		let result = try makeValidator().validate(forged)
		#expect(result == .failure(.signatureInvalid))
	}
	
	@Test("非签发方密钥所签不通过")
	func wrongKeyRejected() throws {
		let forged = try sign(key: P256.Signing.PrivateKey())
		let result = try makeValidator().validate(forged)
		#expect(result == .failure(.signatureInvalid))
	}
	
	@Test("Bundle ID 不匹配不通过")
	func bundleIdMismatchRejected() throws {
		let licenseString = try sign(bundleId: "com.other.app")
		let result = try makeValidator().validate(licenseString)
		#expect(result == .failure(.bundleIdMismatch))
	}
	
	@Test("过期判定按整秒比较（与后台一致）")
	func expiryBoundary() throws {
		let exp = Self.farFutureSeconds
		let licenseString = try sign(exp: exp)
		let validator = try makeValidator()
		// 到达 exp 整秒仍有效因为后台规则：exp >= 当前秒
		let atExpiry = try makeValidator().validate(licenseString, at: Date(timeIntervalSince1970: TimeInterval(exp)))
		#expect(throws: Never.self) { try atExpiry.get() }
		// 超过 exp 一秒后过期
		let afterExpiry = validator.validate(licenseString, at: Date(timeIntervalSince1970: TimeInterval(exp) + 1))
		#expect(afterExpiry == .failure(.expired))
	}
	
	@Test("已过期许可证判 expired")
	func expiredRejected() throws {
		let nowSeconds = UInt32(Date().timeIntervalSince1970)
		let licenseString = try sign(exp: nowSeconds - 10)
		let result = try makeValidator().validate(licenseString)
		#expect(result == .failure(.expired))
	}
	
	@Test("格式非法：空串/坏 base64/旧版两段格式/截断均判 malformed")
	func malformedRejected() throws {
		let validator = try makeValidator()
		#expect(validator.validate("") == .failure(.malformed))
		#expect(validator.validate("!!!") == .failure(.malformed))
		let licenseString = try sign()
		// 旧版两段格式含 '.'，非 base64url 字符
		#expect(validator.validate(licenseString + ".x") == .failure(.malformed))
		// 截断任意 1 个字符：长度与 bundleId 声明不符
		#expect(validator.validate(String(licenseString.dropLast())) == .failure(.malformed))
		// 超长上限
		#expect(validator.validate(licenseString + String(repeating: "A", count: 600)) == .failure(.malformed))
	}
	
	@Test("版本号非法判 malformed（预留演进位）")
	func unsupportedVersionRejected() throws {
		let licenseString = try sign(version: 0x02)
		let result = try makeValidator().validate(licenseString)
		#expect(result == .failure(.malformed))
	}
	
	@Test("字段值非法：exp 为 0 或 bundleId 为空均判 malformed")
	func illegalFieldValueRejected() throws {
		let validator = try makeValidator()
		#expect(validator.validate(try sign(exp: 0)) == .failure(.malformed))
		#expect(validator.validate(try sign(bundleId: "")) == .failure(.malformed))
	}
	
	@Test("bundleId 含引号/反斜杠/中文往返一致")
	func specialCharsInBundleIdRoundTrip() throws {
		let bundleId = "com.godox.\"quoted\"\\slash中文App"
		let licenseString = try sign(bundleId: bundleId)
		let result = try makeValidator(bundleId: bundleId).validate(licenseString)
		let parsed = try #require(try? result.get())
		#expect(parsed.bundleId == bundleId)
	}
	
	@Test("验签兼容补 '=' padding 的输入")
	func paddedLicenseStillVerifies() throws {
		let licenseString = try sign()
		var padded = licenseString
		let remainder = padded.count % 4
		if remainder > 0 { padded += String(repeating: "=", count: 4 - remainder) }
		let result = try makeValidator().validate(padded)
		#expect(throws: Never.self) { try result.get() }
	}
}
