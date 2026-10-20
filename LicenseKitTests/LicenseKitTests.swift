//
//  LicenseKitTests.swift
//  LicenseKitTests
//
//  Created by 杨俊艺 on 2026/10/20.
//

import Foundation
import Testing
import CryptoKit
import Testing
@testable import LicenseKit

/// LicenseValidator 校验全链路测试（签发逻辑测试内联实现：LicenseKit 不随客户端分发签发器）
struct LicenseValidatorTests {
	
	/// 临时密钥对（每次测试全新生成不依赖任何硬编码密钥）
	private let privateKey = P256.Signing.PrivateKey()
	private static let testBundleId = "com.test.app"
	private static let farFuture = Date(timeIntervalSince1970: 4_102_444_800) // 2100-01-01
	
	/// 测试内联签发：与签发工具的算法保持一致（payload 段签名 + base64url 拼接）
	private func sign(_ license: License, key: P256.Signing.PrivateKey? = nil) throws -> String {
		let payloadData = try JSONEncoder().encode(license)
		let payloadSegment = LicenseBase64.encode(payloadData)
		let signature = try (key ?? privateKey).signature(for: SHA256.hash(data: Data(payloadSegment.utf8)))
		return payloadSegment + "." + LicenseBase64.encode(signature.derRepresentation)
	}
	
	private func makeValidator(bundleId: String = testBundleId) throws -> LicenseValidator {
		try LicenseValidator(publicKey: privateKey.publicKey.x963Representation, bundleId: bundleId)
	}
	
	private func makeLicense(bundleId: String = testBundleId, exp: TimeInterval = farFuture.timeIntervalSince1970) -> License {
		License(bundleId: bundleId, appKey: "CUST-0001", exp: exp)
	}
	
	// MARK: - 签发-校验往返
	@Test("合法许可证：签发后校验通过且内容完整")
	func validLicenseRoundTrip() throws {
		let licenseString = try sign(makeLicense())
		let result = try makeValidator().validate(licenseString)
		
		let parsed = try #require(try? result.get())
		#expect(parsed.bundleId == Self.testBundleId)
		#expect(parsed.appKey == "CUST-0001")
		#expect(parsed.expiresAt == Self.farFuture)
	}
	
	// MARK: - 篡改与伪造
	@Test("payload 被篡改：验签失败")
	func tamperedPayloadRejected() throws {
		// 用同一把钥匙签两份许可证，拼接出"许可证A的签名 + 许可证B的payload"
		let licenseA = try sign(makeLicense(exp: Self.farFuture.timeIntervalSince1970))
		let licenseB = try sign(makeLicense(exp: 1_000_000_000))
		let segmentA = licenseA.split(separator: ".")[1]
		let segmentB = licenseB.split(separator: ".")[0]
		let forged = "\(segmentB).\(segmentA)"
		
		let result = try makeValidator().validate(forged)
		#expect(result == .failure(.signatureInvalid))
	}
	
	@Test("非签发方密钥所签：验签失败")
	func wrongKeyRejected() throws {
		let forged = try sign(makeLicense(), key: P256.Signing.PrivateKey())
		
		let result = try makeValidator().validate(forged)
		#expect(result == .failure(.signatureInvalid))
	}
	
	// MARK: - Bundle ID 绑定
	@Test("Bundle ID 不匹配：拒绝")
	func bundleIdMismatchRejected() throws {
		let licenseString = try sign(makeLicense(bundleId: "com.other.app"))
		let result = try makeValidator().validate(licenseString)
		#expect(result == .failure(.bundleIdMismatch))
	}
	
	// MARK: - 有效期
	@Test("过期边界：恰好等于 exp 视为过期，exp 之前放行")
	func expiryBoundary() throws {
		let exp = Self.farFuture.timeIntervalSince1970
		let licenseString = try sign(makeLicense(exp: exp))
		let validator = try makeValidator()
		
		// 恰好到达 exp：过期（不含边界）
		let atExpiry = try makeValidator().validate(licenseString, at: Self.farFuture)
		#expect(atExpiry == .failure(.expired))
		
		// exp 前一秒：放行
		let beforeExpiry = validator.validate(licenseString, at: Self.farFuture.addingTimeInterval(-1))
		#expect(throws: Never.self) { try beforeExpiry.get() }
	}
	
	// MARK: - 格式
	@Test("格式非法：无分隔符/坏 base64/非 JSON 均判 malformed")
	func malformedRejected() throws {
		let validator = try makeValidator()
		#expect(validator.validate("no-dot-here") == .failure(.malformed))
		#expect(validator.validate("!!!.???") == .failure(.malformed))
		#expect(validator.validate("a.b.c") == .failure(.malformed))
		#expect(validator.validate("") == .failure(.malformed))
	}
}
