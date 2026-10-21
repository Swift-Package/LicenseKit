//
//  License.swift
//  LicenseKit
//
//  Created by 杨俊艺 on 2026/10/20.
//

import Foundation

/// 许可证模型
public struct License: Equatable {
	
	/// 绑定的 App Bundle ID
	public let bundleId: String
	
	/// 过期时间秒数
	public let exp: TimeInterval
	
	/// 创建许可证模型
	public init(bundleId: String, exp: TimeInterval) {
		self.bundleId = bundleId
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
// 许可证模型：与后台约定一致的紧凑二进制格式，ECDSA P-256 签名后分发离线可验
// 许可证字符串：`base64url(data ‖ signature)` 单段无 padding
//   data      = 版本号(1B,0x01) | exp(uint32 大端,unix秒) | bundleId长度(1B) | bundleId(UTF-8)
//   signature = ECDSA-SHA256(私钥, data) 的 r‖s 原始编码(64B,各32B大端)，签名对象为 data 区原始字节
