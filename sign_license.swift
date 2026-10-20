#!/usr/bin/env swift

import Foundation
import CryptoKit

// MARK: - License 与 LicenseKit 一样
struct License: Codable {
	let bundleId: String
	let appKey: String
	let exp: TimeInterval
}

func base64urlEncode(_ data: Data) -> String {
	data.base64EncodedString()
		.replacingOccurrences(of: "+", with: "-")
		.replacingOccurrences(of: "/", with: "_")
		.replacingOccurrences(of: "=", with: "")
}

func base64urlDecode(_ string: String) -> Data? {
	var base64 = string
		.replacingOccurrences(of: "-", with: "+")
		.replacingOccurrences(of: "_", with: "/")
	let remainder = base64.count % 4
	if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
	return Data(base64Encoded: base64)
}

func fail(_ message: String) -> Never {
	FileHandle.standardError.write("❌ \(message)\n".data(using: .utf8)!)
	exit(1)
}

// MARK: - 子命令
let args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first else {
	fail("缺少子命令：keygen | sign")
}

switch mode {
case "keygen":
	let privateKey = P256.Signing.PrivateKey()
	print("""
	========== 新密钥对（私钥立即离线妥善保管，不要进入任何仓库）==========
	私钥 (rawRepresentation, base64) —— 签发时作为 sign 子命令参数:
	\(privateKey.rawRepresentation.base64EncodedString())
	
	公钥 (x963Representation, base64) —— 替换 LicenseTool.swift 的 embeddedPublicKeyBase64:
	\(privateKey.publicKey.x963Representation.base64EncodedString())
	====================================================================
	""")
	
case "sign":
	// 命名参数解析：--key/--bundle/--appkey 必填，--days 与 --exp 二选一
	var privateKeyBase64: String?
	var bundleId: String?
	var appKey: String?
	var days: Int?
	var exp: TimeInterval?
	var index = 1
	while index < args.count {
		let flag = args[index]
		guard index + 1 < args.count else { fail("参数 \(flag) 缺少值") }
		let value = args[index + 1]
		switch flag {
		case "--key": privateKeyBase64 = value
		case "--bundle": bundleId = value
		case "--appkey": appKey = value
		case "--days": days = Int(value)
		case "--exp": exp = TimeInterval(value)
		default: fail("未知参数：\(flag)")
		}
		index += 2
	}
	guard let privateKeyBase64, let bundleId, let appKey else {
		fail("缺少必需参数：--key / --bundle / --appkey")
	}
	guard days == nil || exp == nil else {
		fail("--days 与 --exp 只能二选一")
	}
	let expiration: TimeInterval
	if let days {
		guard days > 0 else { fail("--days 必须为正整数") }
		expiration = Date().addingTimeInterval(TimeInterval(days) * 86_400).timeIntervalSince1970
	} else if let exp {
		expiration = exp
	} else {
		fail("必须指定有效期：--days <天数> 或 --exp <过期Unix秒>")
	}
	guard let privateKeyData = Data(base64Encoded: privateKeyBase64),
		  let privateKey = try? P256.Signing.PrivateKey(rawRepresentation: privateKeyData) else {
		fail("私钥数据非法")
	}
	let license = License(bundleId: bundleId, appKey: appKey, exp: expiration)
	
	// 签发
	let payloadData = try JSONEncoder().encode(license)
	let payloadSegment = base64urlEncode(payloadData)
	let signature = try privateKey.signature(for: SHA256.hash(data: Data(payloadSegment.utf8)))
	let licenseString = payloadSegment + "." + base64urlEncode(signature.derRepresentation)

	// 自检
	guard let sigData = base64urlDecode(String(licenseString.split(separator: ".")[1])),
		  let sig = try? P256.Signing.ECDSASignature(derRepresentation: sigData),
		  privateKey.publicKey.isValidSignature(sig, for: SHA256.hash(data: Data(payloadSegment.utf8))) else {
		fail("自检失败：刚签发的许可证未通过验签")
	}
	
	print("""
	========== 许可证签发成功（自检通过）==========
	bundleId : \(license.bundleId)
	appKey   : \(license.appKey)
	过期时间  : \(Date(timeIntervalSince1970: license.exp).description)
	许可证字符串（接入方在 didFinishLaunching 调 LicenseTool.configure(...)）:
	\(licenseString)
	==============================================
	""")
default:
	fail("未知子命令：\(mode)，支持 keygen | sign")
}

//  许可证签发工具（签发方离线使用严禁随 SDK/客户端分发私钥）
//
//  用法:
//    swift sign_license.swift keygen
//      生成一对新密钥（仅第一次/重置签发体系时执行）
//
//    swift sign_license.swift sign --key <私钥base64> --bundle <bundleId> --appkey <appKey>
//           (--days <有效天数> | --exp <过期Unix秒>)
//      签发一份客户许可证并自动用对应公钥自检
//
//  示例:
//    swift sign_license.swift sign --key ABcd...== --bundle com.customer.app --appkey CUST-0042 --days 365
//    swift sign_license.swift sign --key ABcd...== --bundle com.customer.app --appkey CUST-0042 --exp 1798675200
