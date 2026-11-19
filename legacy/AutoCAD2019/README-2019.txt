专利附图标号：AutoCAD 2019 测试版 0.2.4-2019

适用：Windows 版完整 AutoCAD 2019，32 位或 64 位。
不适用于 AutoCAD LT 2019、中望或浩辰。
本包已按 .NET Framework 4.7 和官方兼容接口编译，尚未在 AutoCAD 2019 实机验证，供你在另一台电脑测试。
目标电脑无需安装 SDK、开发工具或 .NET 8。

【一次安装，以后自动加载】
1. 把整个 ZIP 解压到一个文件夹。不要在压缩包内部直接运行。
2. 打开 AutoCAD 2019 的任意图纸，结束当前命令或对话框。
3. 双击 Install2019.cmd。看到“Installed: PatentLabel AutoCAD 2019”即完成。
4. 保存当前工作后，退出并重新启动 CAD 2019。
5. 命令行出现“专利附图标号 0.2.4-2019 已加载”，输入 BH 使用。

只需安装一次。打开其它图纸时会自动加载。
安装使用 Windows 自带的 PowerShell，支持 2.0 及以后版本，不需要管理员权限。
文件安装在当前用户的 %APPDATA%\Autodesk\ApplicationPlugins\PatentLabel2019.bundle。
仅为当前 CAD 用户配置添加本插件的受信任目录并开启启动加载；保留其它受信任路径和 SECURELOAD。
其它 CAD 用户配置若未自动加载，在对应配置下再运行一次安装。
本包使用独立的 2019 插件目录及版本范围，不替换 2014 或 2026 插件。

【操作】
BH：点击引线指向点，移动鼠标预览整条折线和编号，再点击编号中心。
首条默认 1，可以不输入、直接空格或回车确认；之后默认编号递增。
每条确认后命令结束；再按一次空格，由 CAD 重复 BH，开始下一条。
支持 123、1000、A、A01 等编号，最多 32 个字符，不是只能输入到 32。
默认黑体、不附加加粗。BHSZ 可设置字高、折线长度、间隙、确认键和字重。
BHXG：点选已有标号，在命令行改号，同时更新引线间隙。
BHJC：把选中标号改为黑体，并选择加粗或不加粗。
BHVER：查看 2019 模块是否加载、CAD 版本和黑体文件位置。
双击使用 CAD 自带的属性窗口，修改后确认关闭；没有插件原位输入框。
Esc 取消本条，U 或 Ctrl+Z 撤销。旧标号和复制件可独立改号。

【若安装窗口提示错误】
先确认运行的是完整版 AutoCAD 2019、已打开图纸、没有未结束的命令。
保留安装窗口中的报错文字。若已安装但没有预览，输入 BHVER 查看模块状态。
临时手动加载：NETLOAD 选择解压包内
PatentLabel2019.bundle\Contents\Windows\PatentLabel.UI2019.0.2.4.2019.dll。
同目录的 PatentLabel2019.lsp 应自动加载；若没有，再 APPLOAD 加载该 LSP。
不要更改或用记事本另存 LSP：它使用中文 Windows 环境下 CAD 2019 所需的 GBK 编码。

【卸载自动加载】
打开 CAD 2019 图纸，双击 Uninstall2019.cmd，然后重启 CAD。
卸载禁用自动加载，保留文件与备份，只清理由安装器新增的设置。

【开发与验证边界】
编译目标：.NET Framework 4.7 / AnyCPU，不依赖 System.Text.Json 或 .NET 8。
引用来自 Autodesk 官方 AutoCAD.NET.Core / AutoCAD.NET.Model 23.0.0 参考包，对应 AutoCAD 2019 API。
SDK 参考文件仅用于编译，没有打包到此安装包中。
官方兼容表：https://help.autodesk.com/cloudhelp/2020/ENU/AutoCAD-Customization/files/GUID-A6C680F2-DE2E-418A-A182-E4884073338A.htm
官方参考包：https://www.nuget.org/packages/AutoCAD.NET.Core/23.0.0
编译通过、旧编码后端检查及安装脚本检查，不等于 CAD 2019 的实机测试通过。
实际鼠标预览、第二次点击后预览保留、安装自启动、改号及保存重开请按 TEST-2019.txt 检查。
