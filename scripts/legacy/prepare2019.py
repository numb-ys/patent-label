"""Prepare the isolated 2019 sources, installer and localized trial notes."""
from pathlib import Path

from importlib.util import spec_from_file_location, module_from_spec

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = "{ADB4DE6C-B867-4BBC-A3F6-862C78387076}"
UPGRADE = "{7C725465-69E5-42B2-86FD-8DF2E6A90A5E}"


def prepare():
    spec = spec_from_file_location("legacy_prepare", Path(__file__).with_name("prepare-sources.py"))
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    module.prepare(2019)
    source = ROOT / "legacy/AutoCAD2014"
    target = ROOT / "legacy/AutoCAD2019"
    for name in ["Install2014.ps1", "Install2014.cmd", "Uninstall2014.cmd", "PackageContents.xml", "README-2014.txt", "TEST-2014.txt"]:
        original = (source / name).read_text(encoding="utf-8-sig")
        content = original.replace("2014", "2019").replace("19.1", "23.0")
        content = content.replace("{DC15BCC6-A227-43B0-9E47-B1B772FE48ED}", PRODUCT)
        content = content.replace("{8AB733B4-382A-4837-BF72-E949C84819DC}", UPGRADE)
        if name == "Install2014.ps1":
            start = content.index("function Get-CadDocument {")
            end = content.index("\nfunction Get-FileDigest", start)
            content = content[:start] + '''function Get-RunningCadApp([string]$ProgId) {
    return [Runtime.InteropServices.Marshal]::GetActiveObject($ProgId)
}

function Get-CadDocument {
    $script:cad = $null
    # 2019 alone may register .23; a side-by-side 2020 install may redirect it.
    foreach ($progId in @('AutoCAD.Application.23.0','AutoCAD.Application.23','AutoCAD.Application')) {
        try {
            $candidate = Get-RunningCadApp $progId
            $cadVersion = [string](Invoke-CadCall { $candidate.Version })
            if ($cadVersion.StartsWith('23.0')) { $script:cad = $candidate; break }
        }
        catch { }
    }
    if ($null -eq $script:cad) { throw 'Open AutoCAD 2019 and any drawing, then run Install2019.cmd again. Other CAD versions are not configured.' }
    try { return (Invoke-CadCall { $script:cad.ActiveDocument }) }
    catch { throw 'Open any drawing in AutoCAD 2019 and finish the current command, then retry.' }
}
''' + content[end:]
        if name.startswith("README"):
            content = content.replace(".NET Framework 4.0", ".NET Framework 4.7")
            content = content.replace("中文 Windows 2019 所需", "中文 Windows 环境下 CAD 2019 所需")
            content = content.replace("不替换 2026 插件。", "不替换 2014 或 2026 插件。")
            start = content.index("引用来自 Autodesk 官方 ObjectARX")
            end = content.index("编译通过、旧编码后端检查", start)
            content = content[:start] + (
                "引用来自 Autodesk 官方 AutoCAD.NET.Core / AutoCAD.NET.Model 23.0.0 参考包，对应 AutoCAD 2019 API。\n"
                "SDK 参考文件仅用于编译，没有打包到此安装包中。\n"
                "官方兼容表：https://help.autodesk.com/cloudhelp/2020/ENU/AutoCAD-Customization/files/GUID-A6C680F2-DE2E-418A-A182-E4884073338A.htm\n"
                "官方参考包：https://www.nuget.org/packages/AutoCAD.NET.Core/23.0.0\n"
            ) + content[end:]
        destination = target / name.replace("2014", "2019")
        encoded = content.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")
        destination.write_bytes((b"\xef\xbb\xbf" if name.endswith(".txt") else b"") + encoded)
    # Keep the installer regression cases version-specific and avoid opening any CAD session.
    tests = (ROOT / "tests/test_installer2014.ps1").read_text(encoding="utf-8").replace("2014", "2019")
    marker = "    $env:APPDATA = Join-Path $testRoot 'ForeignOwner'"
    extra = '''    function Get-RunningCadApp([string]$ProgId) {
        if ($script:fakeRunningApps.ContainsKey($ProgId)) { return $script:fakeRunningApps[$ProgId] }
        throw 'Not running'
    }
    $targetDoc = FakeDocument 'D:\\Untouched' 12
    $app2019 = New-Object PSObject -Property @{Version='23.0s'; ActiveDocument=$targetDoc}
    $app2020 = New-Object PSObject -Property @{Version='23.1s'; ActiveDocument=(FakeDocument 'D:\\Other' 12)}
    $script:fakeRunningApps = @{'AutoCAD.Application.23'=$app2019}
    Check ([object]::ReferenceEquals((Get-CadDocument), $targetDoc)) 'recognizes-original-2019-dot23-progid'
    $script:fakeRunningApps = @{'AutoCAD.Application.23.0'=$app2019; 'AutoCAD.Application.23'=$app2020}
    Check ([object]::ReferenceEquals((Get-CadDocument), $targetDoc)) 'uses-specific-2019-progid-with-2020-installed'
    $script:fakeRunningApps = @{'AutoCAD.Application.23'=$app2020; 'AutoCAD.Application'=$app2019}
    Check ([object]::ReferenceEquals((Get-CadDocument), $targetDoc)) 'validates-version-before-accepting-fallback'
    $script:fakeRunningApps = @{'AutoCAD.Application'=$app2020}
    $rejectedVersion = $false
    try { $null = Get-CadDocument } catch { $rejectedVersion = $true }
    Check $rejectedVersion 'rejects-wrong-cad-release'
    Check ($targetDoc.Vars['TRUSTEDPATHS'] -eq 'D:\\Untouched') 'version-detection-does-not-change-profile'

'''
    assert marker in tests
    tests = tests.replace(marker, extra + marker)
    (ROOT / "tests/test_installer2019.ps1").write_text(tests, encoding="utf-8")


if __name__ == "__main__":
    prepare()
