# PageLoom · Windows 打包说明

PageLoom 的桌面界面基于 Flutter 构建。在 Windows 10 / 11 x64 上打开解压目录中的 **PDFMathTranslate.exe**。移动或复制时请保留整个目录。目录包含 Flutter、Python、翻译引擎、排版模型、字体和 VC++ 运行库。

1. 在「翻译工作台」选择 PDF、源语言和目标语言。可选页码范围、单语或双语输出。
2. 在「翻译设置」选择 Web 版提供的翻译服务，配置请求速率、术语提取、CSV 术语表、PDF 输出和高级排版。默认使用 Bing。在线服务需要联网，部分服务需要 API Key 或另行部署服务。
3. 点击「保存设置」可保留配置。设置文件使用 Windows 用户级加密，API Key 随配置一起加密保存。
4. 点击蓝色播放按钮。完成后可打开 PDF、已生成的术语表或输出目录。每个任务使用单独的输出子目录，避免覆盖已有结果。
5. 「运行日志」实时显示后台进度、警告和错误，支持筛选、复制和清空。日志只保留在当前会话。「任务记录」保存在当前 Windows 用户的数据目录。
6. 在「设置」选择跟随系统、亮色或暗色主题，以及 MiSans、HarmonyOS Sans 或微软雅黑 UI。外观选择自动保存。「关于」提供版本、项目链接和字体许可。

## 源码目录

| 路径 | 用途 |
| --- | --- |
| `desktop/lib/` | Flutter 界面、翻译设置和任务记录 |
| `desktop/windows/` | Windows 启动器和系统接口 |
| `desktop/backend/bridge.py` | 连接 Flutter 与 PDFMathTranslate-next Python API |
| `desktop/package-windows.ps1` | 构建并组装 Windows x64 发布包 |
| `pdf2zh_next/` | PDFMathTranslate-next 翻译引擎与 Web 界面 |

SDK、下载的运行时和测试产物可放在仓库根目录的 `.tools/`。生成的发布包放在 `dist/`。这两个目录均已排除在 Git 之外。

<a id="from-source"></a>

## 从源码打包

准备 Flutter Windows SDK（已验证版本为 3.41.9）、Visual Studio 2022 的 C++ 桌面构建工具和 Windows SDK。下载并解压[官方 v2.9.0 / BabelDOC v0.6.4 的 with-assets-win64 发布包](https://github.com/PDFMathTranslate-next/PDFMathTranslate-next/releases/tag/v2.9.0)。

从仓库根目录运行以下命令。VCRedistX64 指向包含 Microsoft.VC143.CRT 和 Microsoft.VC143.OpenMP 的 MSVC x64 目录。

    ./desktop/package-windows.ps1 -Flutter <flutter.bat> -EngineDirectory <解压后的pdf2zh目录> -VCRedistX64 <MSVC重分发x64目录>

打包脚本会从官方渠道下载原版 [MiSans](https://hyperos.mi.com/font/zh/download/) 和 [HarmonyOS Sans](https://developer.huawei.com/consumer/cn/design/resource/) 界面字体并验证校验值。直接运行 `flutter build` 或 `flutter run` 前，先执行 `./desktop/fetch-fonts.ps1`。

成功后生成 dist/PDFMathTranslate-Windows-x64。项目按仓库根目录中的 AGPL-3.0 许可证发布。
