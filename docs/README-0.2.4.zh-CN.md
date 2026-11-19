# 专利附图标号（PatentLabel 0.2.4）

两次点击定位引线指向点与编号中心，然后输入编号或接受建议编号，按空格确认。每次只完成一条，确认后命令结束；再按空格，由 CAD 自带的重复命令重新启动 `BH`。

本次更新让第一条默认 `1` 也能直接确认，新建编号默认使用黑体、常规字重。移除自制原位输入框、双击事件处理和默认编辑命令拦截，改用命令行 `BHXG` 或 CAD 原生属性编辑窗口。

## 加载与更新

交互模块用于 Windows 64 位 AutoCAD 2026。

首次安装：打开 AutoCAD 2026 的任意图纸，运行包根目录的 `Install-AutoLoad.cmd`，看到 `Installed: true` 后重启 CAD。以后启动和打开其它图纸时会自动加载，直接输入 `BH` 使用。

安装位置为 `%APPDATA%\Autodesk\ApplicationPlugins\PatentLabel.bundle`。安装脚本只追加本插件目录到受信任路径，并开启启动加载位；保留其它设置与 `SECURELOAD`。不需要管理员权限。

对于已安装且启用的同一插件，可在 CAD 关闭时只更新文件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-autoload.ps1 -Action Install -UpdateFilesOnly
```

这个模式不连接 CAD、不修改配置。更新使用带版本的 DLL，备份被替换的文件。**更新后必须重新启动 CAD**；仅重新加载 LSP 无法卸载旧 DLL 中的双击处理。启动提示应为“专利附图标号 0.2.4 已加载”。

临时加载：在新启动的 CAD 中 `NETLOAD` 加载包内 `src/PatentLabel.UI.dll`，其同目录必须有 `PatentLabel.lsp`。如果 LSP 未自动加载，再用 `APPLOAD` 加载它。只加载 LSP 也可做基础标号；整条折线预览需要配套 DLL。

卸载自动加载：打开任意 CAD 图纸，运行 `Uninstall-AutoLoad.cmd` 后重启。脚本禁用清单、移除本插件新增的信任路径，保留文件及备份。采用 Autodesk 的[插件包自动加载方式](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-Customization/files/GUID-5E50A846-C80B-4FFD-8DD3-C20B22098008.htm)。

## 标号流程

1. 输入 `BH`，点击引线指向位置。
2. 移动鼠标，预览两段折线和建议编号，点击编号中心位置。
3. 首条建议编号为 `1`，之后建议递增。可以直接空格或回车确认，也可输入其它编号覆盖建议。输入期间预览保留，确认后变成正式标号，命令结束。
4. 下一条再按一次空格或回车。此按键由 CAD 的重复命令处理；期间若执行了其它命令，空格会重复那个命令。

支持 `123`、`1000`、`A`、`a`、`A01`、`12A` 等编号，同一个编号可以重复使用。上限为 32 个字符，不是数字只能输入到 32。不接受空格。数字前导零与字母前缀保留，如 `001 → 002`、`A99 → A100`；字母按 `A → B`、`Z → AA`、`12A → 12B` 递增。

在第一个点提示处空回车结束，输入 `S` 打开设置；第二个点处空回车取消本条。Esc 随时退出，未确认的标号不写入图纸。完成一条后可在 CAD 命令行用 `U` 或 `Ctrl+Z` 撤销。

## 修改编号

输入 `BHXG`，点选标号的引线或数字，在命令行输入新编号，按空格或回车确认。直接确认保留原编号，Esc 取消。引线会按新编号宽度调整间隙，复制后的标号可独立修改。

双击使用 CAD 自带的属性编辑窗口，修改后确认关闭。插件不再接管双击。原生属性编辑只改文字，不重新计算引线；需要同步调整引线时使用 `BHXG`。

## 字体与设置

新建编号默认使用 **黑体（SimHei），不额外加粗**。新版单独保存黑体字重设置，不沿用旧版的默认粗体。`BHSZ` 最后一项选 `Regular`（不加粗）或 `Bold`（加粗），对之后新建的标号生效。

旧标号保留原外观；普通改号会保留该条的字体与字重。需要把已有标号改为黑体时，输入 `BHJC`，选择标号，再选择字重。文字与引线间隙会重新计算，引线粗细不变。配套 DLL 提供真实的字体字重设置；纯 LSP 基础模式使用黑体文件，两个样式的加粗外观可能相同。

| 命令 | 用途 |
| --- | --- |
| `BH` | 单次两点标号，确认结束，下次用 CAD 原生空格重复 |
| `BHSZ` | 字高、水平段长度、文字间隙、确认键和新建编号字重 |
| `BHXG` | 命令行改号，同步更新引线 |
| `BHJC` | 把已有标号改为黑体，并选择加粗或不加粗 |
| `BHHELP` | 命令帮助 |

长度按图纸单位输入，空回车保留原值。默认字高 `2.5`、水平段长度 `3.75`、间隙 `0.8`。确认键支持 `Space`（空格或回车，默认）与 `Enter`（仅回车）。设置保存在 CAD 当前用户配置。

编号位置为文字中心，左右自动折线，默认无箭头。每条标号是包含折线和 `NUMBER` 属性的独立匿名块，可用 MOVE、COPY、ERASE 整体操作。使用 `PATENT_LABEL` 图层，需启用并解锁。新版字体样式为 `PATENT_LABEL_SIMHEI_REGULAR`、`PATENT_LABEL_SIMHEI_BOLD`；保留旧样式以兼容已有标号。使用当前 UCS 与当前空间，没有引线自动避让或打印比例自动换算。

## 验证与开发

自动检查使用 AutoCAD 2026 Core Console、隔离配置和临时图纸，不操作桌面或工作图纸。覆盖首条空格确认、原生空格重复、递增编号、字体文件与字重、预览与坐标、改号、复制、撤销、UCS 和保存重开。实际鼠标跟随与 CAD 属性编辑窗口由用户试用，步骤见“试用检查.md”；内核检查不能证明所有桌面崩溃都已消除。

其它 CAD 版本、AutoCAD LT、中望和浩辰尚未验证。LSP 为 UTF-8，需要 `LISPSYS=1` 或 `2`，插件不修改该设置。

`src/PatentLabel.lsp` 负责 DWG 创建与修改，`src/PatentLabel.UI` 是 .NET 8 预览模块。构建需要 .NET SDK 和本机 AutoCAD 2026 托管程序集，`AutoCADDir` 可指定安装目录。

```powershell
dotnet build .\src\PatentLabel.UI\PatentLabel.UI.csproj -c Release
py -3 scripts/test_plugin.py
py -3 scripts/test_ui.py
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\package.ps1
```

打包输出 `dist/PatentLabel-0.2.4-autoload.zip`，包括 DLL、LSP、安装/卸载脚本、清单、说明与试用步骤。交互 API 参考 Autodesk 的 [DrawJig](https://help.autodesk.com/cloudhelp/2026/ENU/OARX-ManagedRefGuide/files/OARX-ManagedRefGuide-Autodesk_AutoCAD_EditorInput_DrawJig.html) 和 [getstring](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-AutoLISP-Reference/files/GUID-B139EFBD-74B7-4276-B422-D2186F7D8D0A.htm) 文档。
