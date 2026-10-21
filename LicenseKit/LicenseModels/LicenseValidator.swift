//
//  LicenseValidator.swift
//  LicenseKit
//
//  Created by 杨俊艺 on 2026/10/20.
//

import Foundation
import CryptoKit

/// 许可证校验器
struct LicenseValidator {
	
	/// 许可证二进制格式版本（预留升级空间）
	private static let formatVersion: UInt8 = 0x01
	/// 除 bundleId 外的固定开销：版本(1) + exp(4) + bundleId长度(1) + 签名(64)
	private static let fixedLength = 1 + 4 + 1 + 64
	/// 许可证字符串防御性长度上限
	private static let licenseMaxLength = 512
	
	private let bundleId: String
	private let publicKey: P256.Signing.PublicKey
	
	/// 创建校验器
	///
	/// - Parameters:
	///   - publicKey: 签发方公钥（P-256，`x963Representation` 格式）
	///   - bundleId: 期望绑定的 Bundle ID，默认取当前 App 主包
	/// - Throws: 公钥数据非法时抛出
	init(publicKey: Data, bundleId: String = Bundle.main.bundleIdentifier ?? "") throws {
		self.publicKey = try P256.Signing.PublicKey(x963Representation: publicKey)
		self.bundleId = bundleId
	}
	
	/// 校验许可证字符串
	///
	/// 校验顺序与后台 LicenseUtil.verify 保持一致：结构解析 → 字段校验 → 过期校验 → 公钥验签， 最后附带 SDK 侧特有的 Bundle ID 绑定校验
	///
	/// - Parameters:
	///   - license: 许可证字符串（`base64url(data ‖ signature)` 单段）
	///   - date: 校验基准时间（默认当前时间）
	/// - Returns: 成功返回解析出的 ``License``，失败返回具体原因
	func validate(_ license: String, at date: Date = Date()) -> Result<License, LicenseError> {
		let trimmed = license.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty,
			  trimmed.count <= Self.licenseMaxLength,
			  let data = LicenseBase64.decode(trimmed),
			  data.count >= Self.fixedLength + 1,
			  data[0] == Self.formatVersion else {
			return .failure(.malformed)
		}
		let exp = (UInt32(data[1]) << 24) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 8) | UInt32(data[4])
		let bundleIdLength = Int(data[5])
		// 长度必须与 bundleId 声明完全一致防截断/拼接
		guard bundleIdLength > 0,
			  data.count == Self.fixedLength + bundleIdLength,
			  exp > 0,
			  let bundleId = String(data: data[6..<(6 + bundleIdLength)], encoding: .utf8) else {
			return .failure(.malformed)
		}
		// 过期校验先于验签
		let nowEpochSeconds = UInt64(max(0, date.timeIntervalSince1970))
		guard UInt64(exp) >= nowEpochSeconds else { return .failure(.expired) }
		let signatureOffset = 6 + bundleIdLength
		guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: data[signatureOffset...]),
			  publicKey.isValidSignature(signature, for: SHA256.hash(data: data[..<signatureOffset])) else {
			return .failure(.signatureInvalid)
		}
		guard bundleId == self.bundleId else { return .failure(.bundleIdMismatch) }
		return .success(License(bundleId: bundleId, exp: TimeInterval(exp)))
	}
}
