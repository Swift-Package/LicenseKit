#!/usr/bin/env swift

import Foundation
import CryptoKit

// MARK: - 许可证二进制格式
// license = base64url(data ‖ signature)，单段无 padding
//   data      = 版本号(1B,0x01) | exp(uint32 大端,unix秒) | bundleId长度(1B) | bundleId(UTF-8)
//   signature = ECDSA-SHA256(私钥, data) 的 r‖s 原始编码(64B,各32B大端)

let formatVersion: UInt8 = 0x01

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
	========== 新密钥对（私钥立即离线妥善保管不要进入任何仓库）==========
	私钥 (rawRepresentation, base64) —— 签发时作为 sign 子命令参数（后台兼容 PKCS8）:
	\(privateKey.rawRepresentation.base64EncodedString())
	
	公钥 (x963Representation, base64) —— 替换 LicenseTool.swift 的 embeddedPublicKeyBase64（后台兼容 X509 SPKI）:
	\(privateKey.publicKey.x963Representation.base64EncodedString())
	====================================================================
	""")
	
case "sign":
	// 命名参数解析：--key/--bundle 必填，--days 与 --exp 二选一
	var privateKeyBase64: String?
	var bundleId: String?
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
		case "--days": days = Int(value)
		case "--exp": exp = TimeInterval(value)
		default: fail("未知参数：\(flag)")
		}
		index += 2
	}
	guard let privateKeyBase64, let bundleId else {
		fail("缺少必需参数：--key / --bundle")
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
	guard expiration > 0, expiration <= TimeInterval(UInt32.max) else {
		fail("有效期非法（需为正的 unix 秒，且在 uint32 范围内）")
	}
	let bundleIdBytes = Array(bundleId.utf8)
	guard !bundleIdBytes.isEmpty, bundleIdBytes.count <= 0xFF else {
		fail("bundleId 非法（UTF-8 长度需为 1~255 字节）")
	}
	guard let privateKeyData = Data(base64Encoded: privateKeyBase64),
		  let privateKey = try? P256.Signing.PrivateKey(rawRepresentation: privateKeyData) else {
		fail("私钥数据非法")
	}
	
	// 组装 data 区：版本号 | exp(uint32 大端) | bundleId长度 | bundleId
	let expSeconds = UInt32(expiration)
	var data = Data([formatVersion])
	data.append(UInt8((expSeconds >> 24) & 0xFF))
	data.append(UInt8((expSeconds >> 16) & 0xFF))
	data.append(UInt8((expSeconds >> 8) & 0xFF))
	data.append(UInt8(expSeconds & 0xFF))
	data.append(UInt8(bundleIdBytes.count))
	data.append(contentsOf: bundleIdBytes)
	
	// 签发：签名对象为 data 区原始字节，取 r‖s 原始编码(64B)
	let signature = try privateKey.signature(for: SHA256.hash(data: data))
	var licenseData = data
	licenseData.append(signature.rawRepresentation)
	let licenseString = base64urlEncode(licenseData)
	
	// 自检：解析刚签发的许可证并用对应公钥验签
	guard let decoded = base64urlDecode(licenseString), decoded == licenseData,
		  let parsedSignature = try? P256.Signing.ECDSASignature(rawRepresentation: signature.rawRepresentation),
		  privateKey.publicKey.isValidSignature(parsedSignature, for: SHA256.hash(data: data)) else {
		fail("自检失败：刚签发的许可证未通过验签")
	}
	
	print("""
	========== 许可证签发成功（自检通过）==========
	bundleId : \(bundleId)
	过期时间  : \(Date(timeIntervalSince1970: TimeInterval(expSeconds)).description)
	长度     : \(licenseString.count) 字符
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
//    swift sign_license.swift sign --key <私钥base64> --bundle <bundleId>
//           (--days <有效天数> | --exp <过期Unix秒>)
//      签发一份客户许可证并自动用对应公钥自检
//
//  示例:
//    swift sign_license.swift sign --key ABcd...== --bundle com.customer.app --days 365
//    swift sign_license.swift sign --key ABcd...== --bundle com.customer.app --exp 1798675200
