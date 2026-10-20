//
//  License.swift
//  LicenseKit
//
//  Created by 杨俊艺 on 2026/10/20.
//

import Foundation

/// 许可证模型
public struct License: Codable, Equatable {
	
	/// 绑定的 App Bundle ID（不匹配则拒绝）
	public let bundleId: String
	
	/// 客户标识（签发方分配）
	public let appKey: String
	
	/// 过期时间秒数
	public let exp: TimeInterval
	
	/// 创建许可证模型
	public init(bundleId: String, appKey: String, exp: TimeInterval) {
		self.bundleId = bundleId
		self.appKey = appKey
		self.exp = exp
	}
	
	/// 过期时间
	public var expiresAt: Date {
		Date(timeIntervalSince1970: exp)
		/// 根据给定的秒数创建一个相对于1970年1月1日00:00:00 UTC的日期值
	}
}

// MARK: - base64url 编解码（本模块内部工具）与标准 base64 差异为 `+/` → `-_` 且无尾部 `=` 填充
enum LicenseBase64 {
	static func encode(_ data: Data) -> String {
		data.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}
	
	static func decode(_ string: String) -> Data? {
		var base64 = string
			.replacingOccurrences(of: "-", with: "+")
			.replacingOccurrences(of: "_", with: "/")
		// 补回填充
		let remainder = base64.count % 4
		if remainder > 0 {
			base64 += String(repeating: "=", count: 4 - remainder)
		}
		return Data(base64Encoded: base64)
	}
}

// MARK: - 说明
// 许可证模型：payload 自包含，经 ECDSA P-256 签名后分发离线可验
// 许可证字符串格式：`base64url(payloadJSON).base64url(derSignature)` 签名内容为 payload 段的 UTF-8 字节
