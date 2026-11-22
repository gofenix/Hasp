# Hasp v0.1.1-preview.1

- 一键收起菜单栏后，Hasp 会自动收起新出现的状态栏图标。
- 日出日落模式正确处理跨午夜的日落，以及高纬度地区的极昼和极夜。
- 官网更新了安装步骤和权限说明。

本预览版需要 macOS 26.0 或更高版本，ZIP 同时包含 Apple Silicon 和 Intel 架构。解压后将完整的 `Hasp.app` 拖入“应用程序”。安装包校验值见 `SHA256SUMS.txt`，构建信息见 `BUILD-INFO.json`。

安装包已使用 Developer ID 签名，**尚未完成 Apple 公证**。macOS Gatekeeper 会阻止常规打开。请先核对来源和校验值，并阅读 [Apple 的首次打开说明](https://support.apple.com/102445)。

本次使用 Xcode 27.2 和 Swift 6.4.2 构建。验证范围和结果见随包附带的 `BUILD-INFO.json`。
