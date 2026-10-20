//
//  LicenseValidator.swift
//  LicenseKit
//
//  Created by 杨俊艺 on 2026/10/20.
//

import Foundation
import CryptoKit

/// 许可证校验器：解析 + 验签 + Bundle ID 比对 + 过期校验，全程离线
///
/// 复用方式：接入方注入**自己的**公钥与 Bundle ID，组件内不含任何厂商特定值
public struct LicenseValidator {
	
	private let bundleId: String
	private let publicKey: P256.Signing.PublicKey
	
	/// 创建校验器
	///
	/// - Parameters:
	///   - publicKey: 签发方公钥（P-256，`x963Representation` 格式）
	///   - bundleId: 期望绑定的 Bundle ID，默认取当前 App 主包
	/// - Throws: 公钥数据非法时抛出
	public init(publicKey: Data, bundleId: String = Bundle.main.bundleIdentifier ?? "") throws {
		self.publicKey = try P256.Signing.PublicKey(x963Representation: publicKey)
		self.bundleId = bundleId
	}
	
	/// 校验许可证字符串
	///
	/// - Parameters:
	///   - license: 许可证字符串（`base64url(payload).base64url(signature)`）
	///   - date: 校验基准时间（默认当前时间；测试注入以覆盖过期边界）
	/// - Returns: 成功返回解析出的 ``License``，失败返回具体原因
	public func validate(_ license: String, at date: Date = Date()) -> Result<License, LicenseError> {
		let segments = license.split(separator: ".", omittingEmptySubsequences: false)
		guard segments.count == 2 else { return .failure(.malformed) }
		
		let payloadSegment = String(segments[0])
		guard let payloadData = LicenseBase64.decode(payloadSegment),
			  let signatureData = LicenseBase64.decode(String(segments[1])),
			  let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
			  let parsed = try? JSONDecoder().decode(License.self, from: payloadData) else {
			return .failure(.malformed)
		}
		
		// 验签：签名输入为 payload 段的 UTF-8 字节（与 LicenseSigner 约定一致）
		guard publicKey.isValidSignature(signature, for: SHA256.hash(data: Data(payloadSegment.utf8))) else {
			return .failure(.signatureInvalid)
		}
		
		guard parsed.bundleId == bundleId else { return .failure(.bundleIdMismatch) }
		guard parsed.expiresAt > date else { return .failure(.expired) }
		return .success(parsed)
	}
}
