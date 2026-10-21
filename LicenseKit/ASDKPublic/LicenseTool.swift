//
//  LicenseTool.swift
//  LicenseKit
//
//  Created by 杨俊艺 on 2026/10/20.
//

import Foundation

/// SDK 鉴权入口
public enum LicenseTool {
	
	/// 鉴权状态
	public enum State {
		/// 未调用 configure 或无缓存
		case unconfigured
		/// 校验通过
		case valid(License)
		/// 校验失败
		case invalid(LicenseError)
	}
	
	/// 签发公钥（P-256 x963，base64）
	/// ⚠️ 分发前替换为正式公钥
	private static let embeddedPublicKeyBase64 = "BMIMk1+c9WIeXgmIxYZ/t6meHk2gpvbKNb9N+qpBe38p2GAoq9PepOw/V2gFCqWMcox57WluyXFvdSXYjh526uw="
	
	/// 当前鉴权状态
	public private(set) static var state: State = .unconfigured
	
	/// ⚠️检测当前是否已经验证通过
	public static var isValid: Bool {
		if case .valid = state {
			return true
		}
		return false
	}
	
	/// 校验失败的具体原因
	public static var failureError: LicenseError? {
		if case .invalid(let error) = state {
			return error
		}
		return nil
	}
	
	/// 每次启动传入许可证字符串重新验签
	/// - Parameter license: 许可证字符串
	public static func configure(_ license: String) {
		guard let publicKeyData = Data(base64Encoded: embeddedPublicKeyBase64),
			  let validator = try? LicenseValidator(publicKey: publicKeyData) else {
			state = .invalid(.malformed)
			return
		}
		switch validator.validate(license) {
		case .success(let parsed):
			state = .valid(parsed)
		case .failure(let error):
			state = .invalid(error)
		}
	}
}

// MARK: - 使用说明
// 接入方调用一次 ``configure(_:)``，之后在要校验的代码读取 ``isValid`` 就能确定是否通过
// 许可证由签发方私钥签名SDK 用内嵌公钥验签无需联网
