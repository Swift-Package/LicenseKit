# ``LicenseKit``

离线许可证校验 SDK：签发方用私钥签发许可证，App 用内嵌公钥本地验签全程无需联网

## Overview

LicenseKit 解决一个问题：**你的 SDK / App 只允许付费客户用**。

核心概念只有三个：

- **许可证字符串**：一串形如 `xxxxx.yyyyy` 的文本，里面写明了绑定的 App、客户标识、有效期，并由签发方私钥签名，改一个字符都会验签失败
- **签发方**：你自己（SDK 作者）。用仓库根目录的 `sign_license.swift` 脚本给客户签发许可证，**私钥永远留在你手里绝不分发**
- **接入方**：你的客户（App 开发者）。在 App 里引入 LicenseKit，启动时传入许可证字符串，之后在任何要控制权限的地方检查是否通过

工作流程（全程离线）：

```
签发方：私钥签名 → 许可证字符串 → 发给客户（邮件/后台下发均可）
接入方：App 启动 → LicenseTool.configure(许可证字符串) → 本地验签
业务处：LicenseTool.isValid == true 才放行功能
```

---

## 小白使用说明

### 一、我是接入方（我的 App 要接入 LicenseKit）

#### 第 1 步：把 SDK 加进工程

用 Swift Package Manager 添加本仓库（或拖入构建好的 `LicenseKit.xcframework`）：

1. Xcode 菜单 `File → Add Package Dependencies...`
2. 填入本仓库地址，选中 `LicenseKit` 库
3. 勾选到你的 App Target

#### 第 2 步：向签发方要许可证字符串

找签发方（提供 SDK 给你的人）要一串许可证字符串，长这样：

```
eyJidW5kbGVJZCI6ImNvbS5leGFtcGxlLmFwcCIsImFwcEtleSI6IkNVU1QtMDAwMSIsImV4cCI6ND...MEUCIQD...
```

> 注意：许可证和你的 App 绑定（Bundle ID 必须一致），换一个 App 用不了；也有有效期，到期自动失效

#### 第 3 步：App 启动时传入许可证

**UIKit App**：在 `AppDelegate` 的 `didFinishLaunching` 里调用一次：

```swift
import LicenseKit

func application(_ application: UIApplication,
                  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    LicenseTool.configure("签发方给你的许可证字符串")
    return true
}
```

**SwiftUI App**：在 `App` 的初始化里调用：

```swift
import SwiftUI
import LicenseKit

@main
struct MyApp: App {
    init() {
        LicenseTool.configure("签发方给你的许可证字符串")
    }
    var body: some Scene { ... }
}
```

> `configure` 内部会做完整校验：验签 → Bundle ID 比对 → 有效期检查。许可证可以硬编码，也可以从自家后台拉取后传入，**每次启动都要重新传**。

#### 第 4 步：在要控制权限的地方检查

```swift
import LicenseKit

if LicenseTool.isValid {
    // ✅ 验证通过，放行付费功能
    unlockProFeatures()
} else {
    // ❌ 验证失败，看具体原因
    let reason = LicenseTool.failureError?.localizedDescription ?? "未配置许可证"
    showLicenseAlert(reason)
}
```

需要许可证详情（客户标识、到期时间）时，从 `state` 里取：

```swift
if case .valid(let license) = LicenseTool.state {
    print("客户：\(license.appKey)")
    print("到期：\(license.expiresAt)")
}
```

#### 验证失败怎么办（排查表）

| 报错 | 含义 | 怎么办 |
|---|---|---|
| `许可证格式非法` | 字符串复制不完整 / 被转义 | 重新完整复制，检查有没有换行、空格 |
| `许可证签名校验失败` | 内容被篡改，或 SDK 公钥与签发私钥不是一对 | 别改许可证内容；签发方检查公私钥是否配套 |
| `许可证与当前应用不匹配` | 许可证绑定的 Bundle ID 和当前 App 不一致 | 找签发方按你 App 的 Bundle ID 重新签发 |
| `许可证已过期` | 超过许可证里的有效期 | 找签发方续期重签 |

---

### 二、我是签发方（我要给客户签发许可证）

#### 第 0 步（只做一次）：生成密钥对

在仓库根目录执行：

```bash
swift sign_license.swift keygen
```

输出一对密钥：

- **私钥**（`rawRepresentation, base64`）：你离线妥善保管，签发时用。**不要提交进任何仓库、不要发给任何人**
- **公钥**（`x963Representation, base64`）：替换 `LicenseTool.swift` 里的 `embeddedPublicKeyBase64` 常量，随 SDK 分发

> ⚠️ 公钥替换后需重新构建 SDK。密钥对一旦投入生产就别再 keygen，否则所有已签发的许可证全部失效。

#### 第 1 步：给客户签发许可证

```bash
# 按天数签发（365 天有效）
swift sign_license.swift sign \
  --key <你的私钥base64> \
  --bundle com.customer.app \
  --appkey CUST-0042 \
  --days 365

# 或指定精确过期时间（Unix 秒）
swift sign_license.swift sign \
  --key <你的私钥base64> \
  --bundle com.customer.app \
  --appkey CUST-0042 \
  --exp 1798675200
```

参数说明：

- `--key`：第 0 步生成的私钥
- `--bundle`：客户 App 的 Bundle ID（必须完全一致，一个客户 App 签一份）
- `--appkey`：你分配给客户的标识，随便定，如 `CUST-0042`
- `--days` / `--exp`：有效期，二选一

脚本会自检签名有效后输出许可证字符串，把它发给客户即可（邮件、后台接口下发都行）。

#### 签发方安全红线

1. 私钥只存在于签发机器（建议离线保管），严禁进入 Git、SDK、客户端
2. 签发脚本 `sign_license.swift` 可以随仓库走（没有私钥它签不出任何东西），但私钥不能
3. 客户报"签名校验失败"且确认没改内容时，先检查 SDK 里的公钥是否是当前私钥配套的那把

---

### 三、许可证的技术细节（选读）

许可证字符串格式：`base64url(payloadJSON) . base64url(derSignature)`

- 签名算法：ECDSA P-256 + SHA-256，签名内容为 payload 段的 UTF-8 字节
- payload 字段：`bundleId`（绑定 App）、`appKey`（客户标识）、`exp`（过期 Unix 秒）
- 校验顺序：格式解析 → 验签 → Bundle ID 比对 → 有效期；任一步失败即拒绝
- 过期边界：恰好到达 `exp` 时刻视为已过期

## Topics

### 鉴权入口

- ``LicenseTool``
- ``LicenseTool/configure(_:)``
- ``LicenseTool/isValid``
- ``LicenseTool/failureError``
- ``LicenseTool/state``

### 数据模型

- ``License``
- ``LicenseError``
