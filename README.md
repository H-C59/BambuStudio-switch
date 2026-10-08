# Bambu Studio 账号切换器

[English README](README_EN.md)

Bambu Studio 多账号图形化管理工具：**一键热切换账号，互不干扰，各自保持登录状态（免重新登录）**。

> 原作者：**H-C59** ｜ 协议：[CC BY-NC 4.0](LICENSE)（署名-非商业性使用）｜ 非官方工具，与 Bambu Lab 无关

---

## 项目目的

Bambu Studio 官方客户端不支持多账号并存：每次换账号都要退出登录再重新登录，打印机绑定、耗材预设等配置也容易混在一起。

本工具利用 Bambu Studio 的一个特性——**登录态（token + 账号预设）完全自包含在数据目录内，且客户端只认 `%APPDATA%\BambuStudio` 这个目录名**——通过目录重命名实现真正的多账号热切换：

- 每个账号的全部数据（登录 token、filament/machine/process 预设）独立存放，互不干扰
- 切换后**无需重新登录**，打开即是目标账号
- 图形化界面，卡片式管理，支持显示账号真实昵称和头像

## 功能特性

- 🔍 **自动发现账号**：自动扫描本机已有的账号配置，读取当前登录的账号 ID
- 🖼️ **头像与昵称**：支持"同步资料"——内嵌浏览器登录一次后自动获取真实昵称和头像（也可手动自定义）
- 🔀 **一键切换**：点击卡片即可切换；Bambu Studio 正在运行时会先询问并自动安全关闭（优雅关闭优先，强杀需二次确认）
- ➕ **添加账号**：引导式添加——自动停放当前配置，启动全新客户端登录新账号后一键入库
- 🛡️ **安全回滚**：所有目录操作失败自动回滚；取消添加不产生垃圾数据
- 📦 **单文件 exe**：内置环境检测，缺失 .NET / WebView2 Runtime 时自动下载补齐，拷贝到任意 Win10/11 机器即用

## 使用教程

### 方式一：直接下载 exe（推荐）

1. 在 [Releases](../../releases) 页面下载 `Bambu账号切换器.exe`
2. 双击运行（首次运行如有 SmartScreen 提示，点"更多信息 → 仍要运行"）
3. exe 会自动检测运行环境，缺失组件时按提示自动安装（需联网）

### 方式二：从源码运行

需要 Windows 10/11（自带 PowerShell 5.1+ 与 .NET Framework 4.6.2+）：

```powershell
# 克隆本仓库后，双击运行
Bambu账号切换器.bat
```

> 注：源码方式运行需要 `webview2-lib\` 目录中的 WebView2 托管 DLL（该目录不入库）。
> 从 [NuGet](https://www.nuget.org/packages/Microsoft.Web.WebView2) 下载 nupkg（zip 格式），
> 取出 `lib/net462/Microsoft.Web.WebView2.Core.dll`、`lib/net462/Microsoft.Web.WebView2.Wpf.dll`
> 和 `build/native/x64/WebView2Loader.dll` 放入 `webview2-lib\` 即可。

### 方式三：自行打包 exe

修改 `BambuAccountSwitcher.ps1` 后重新打包（编译器为 Windows 自带）：

```cmd
cd 项目目录
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe @build.rsp
```

### 界面操作

| 操作 | 说明 |
|---|---|
| **切换账号** | 点击非活动卡片的"切换到此账号"；勾选"切换后自动启动"可切完直接打开客户端 |
| **同步资料** | 弹出内嵌浏览器登录 Bambu 账号（官方登录页，凭据不经过本工具），自动获取昵称+头像；每个账号会话独立，下次免登 |
| **编辑** | 自定义显示名称、手动选择本地图片作为头像 |
| **添加账号** | 点 ＋ 卡片 → 自动启动全新 Bambu Studio → 登录新账号并完全退出 → 回来点"完成添加" |

## 工作原理

```
%APPDATA%\
├── BambuStudio            ← 当前活动账号（客户端只认这个名字）
├── BambuStudio-personal   ← 停放的账号配置 A
├── BambuStudio-work       ← 停放的账号配置 B
└── ...
```

- Bambu Studio 的登录 token 加密存储在数据目录内的 `BambuNetworkEngine.conf`，账号预设在 `user\<uid>\`——全部随目录走，重命名即切换，登录态完整保留
- 每个配置目录内的 `_switcher\profile.json` 保存本工具的元数据（显示名/昵称/头像路径），同样随目录走
- 本工具**不读取、不修改**任何凭据；切换动作只是目录重命名

## 环境要求

| 组件 | 要求 | 缺失时 |
|---|---|---|
| 操作系统 | Windows 10 / 11 | — |
| PowerShell | 5.1+（系统自带） | — |
| .NET Framework | 4.6.2+ | exe 自动引导安装 4.8 |
| WebView2 Runtime | Evergreen 版 | exe 自动下载安装（微软官方组件） |
| Bambu Studio | 已安装（默认路径） | — |

## 注意事项

- 切换账号会先关闭正在运行的 Bambu Studio（会先尝试优雅关闭；仅在卡住且经你确认后才强制结束）
- 某个账号长期不用导致 token 过期时，在客户端里重新登录一次即可，之后继续保留
- "同步资料"需要在内嵌浏览器中登录一次对应账号；不想登录可以只用自定义名称和头像

## 免责声明

本工具为第三方开源项目，与 Bambu Lab 无任何关联。"Bambu Studio"、"Bambu Lab"、"MakerWorld" 名称与商标归其各自所有者。使用本工具造成的任何数据损失，作者不承担责任的，请在理解原理后自行斟酌使用；重要配置建议提前备份 `%APPDATA%\BambuStudio*` 目录。

## 开源协议

[CC BY-NC 4.0](LICENSE) — 署名-非商业性使用 4.0 国际

你可以自由地共享、演绎本作品，惟须遵守：**署名原作者 H-C59**；**不得用于商业目的**。

## 致谢

- 原作者：[H-C59](https://github.com/H-C59)
- 开发协助：Claude (Anthropic)
