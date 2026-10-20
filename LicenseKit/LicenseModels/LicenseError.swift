//
//  LicenseError.swift
//  LicenseKit
//
//  Created by 杨俊艺 on 2026/10/20.
//

import Foundation

/// 许可证校验失败原因
public enum LicenseError: Error, Equatable {
	
	/// 许可证格式非法（无法拆分/解码/解析 JSON）
	case malformed
	
	/// 签名校验失败（内容被篡改或非签发方所签）
	case signatureInvalid
	
	/// 许可证绑定的 Bundle ID 与当前 App 不匹配
	case bundleIdMismatch
	
	/// 许可证已过期
	case expired
}

extension LicenseError: LocalizedError {
	/// 面向用户的可读描述
	public var errorDescription: String? {
		switch self {
		case .malformed: return "许可证格式非法"
		case .signatureInvalid: return "许可证签名校验失败"
		case .bundleIdMismatch: return "许可证与当前应用不匹配"
		case .expired: return "许可证已过期"
		}
	}
}
