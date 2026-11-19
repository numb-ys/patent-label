[CmdletBinding()]
param(
    [ValidateSet(2014,2019,2026)][int]$Year = 2019,
    [Parameter(Mandatory=$true)][string]$PackageDirectory
)
$PackageDirectory = (Resolve-Path -LiteralPath $PackageDirectory).Path
$ExpectedVersion = '0.3.1.' + $Year
$ExpectedDll = if ($Year -eq 2026) { 'PatentLabel.UI.' + $ExpectedVersion + '.dll' } else { 'PatentLabel.UI' + $Year + '.' + $ExpectedVersion + '.dll' }

$ErrorActionPreference = 'Stop'
$originalAppData = $env:APPDATA
$testRoot = Join-Path (Split-Path -Parent $PSScriptRoot) (('artifacts\installer-en-' + $Year + '-') + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$checks = New-Object 'System.Collections.Generic.List[object]'
function Check([bool]$Condition, [string]$Name) {
    $checks.Add(@{name=$Name; passed=$Condition})
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
}
function FakeDocument([string]$Trusted, [int]$Autoload) {
    $doc = New-Object PSObject -Property @{ Vars = @{'TRUSTEDPATHS'=$Trusted; 'APPAUTOLOAD'=$Autoload; 'SECURELOAD'=2} }
    $doc | Add-Member ScriptMethod GetVariable { param($key) return $this.Vars[$key] }
    $doc | Add-Member ScriptMethod SetVariable { param($key,$value) $this.Vars[$key] = $value }
    return $doc
}

try {
    $env:APPDATA = Join-Path $testRoot 'AppData[2019]'
    . (Join-Path $PackageDirectory 'Install.ps1') -LibraryOnly
    $doc = FakeDocument 'C:\Existing;D:\Other' 12
    Install-PatentLabel $doc | Out-Null
    Check (Test-Path -LiteralPath $manifestPath) 'installs-manifest'
    Check (Test-Path -LiteralPath (Join-Path $contentRoot 'PatentLabel.lsp')) 'installs-backend'
    Check (Test-Path -LiteralPath (Join-Path $contentRoot $ExpectedDll)) 'installs-versioned-dll'
    Check ($doc.Vars['TRUSTEDPATHS'] -eq ('C:\Existing;D:\Other;' + $contentRoot)) 'appends-only-exact-plugin-trusted-directory'
    Check ($doc.Vars['APPAUTOLOAD'] -eq 14) 'enables-only-startup-bit'
    Check ($doc.Vars['SECURELOAD'] -eq 2) 'preserves-secureload'
    Check ((Read-InstallState).Version -eq $ExpectedVersion) 'records-version'
    Install-PatentLabel $doc | Out-Null
    Check (@($doc.Vars['TRUSTEDPATHS'] -split ';' | Where-Object { $_ -eq $contentRoot }).Count -eq 1) 'reinstall-does-not-duplicate-trusted-directory'
    Check ((Read-InstallState).AutoLoadBefore -eq 12) 'reinstall-preserves-original-startup-state'
    Check (-not (Test-Path -LiteralPath (Join-Path $bundleRoot 'Backups'))) 'identical-reinstall-does-not-create-backups'
    $doc.Vars['TRUSTEDPATHS'] += ';E:\UserAddedLater'
    Uninstall-PatentLabel $doc | Out-Null
    Check (-not (Test-Path -LiteralPath $manifestPath)) 'uninstall-disables-manifest'
    Check ($doc.Vars['TRUSTEDPATHS'] -eq 'C:\Existing;D:\Other;E:\UserAddedLater') 'uninstall-preserves-other-and-later-trusted-paths'
    Check ($doc.Vars['APPAUTOLOAD'] -eq 12) 'uninstall-restores-only-startup-bit'
    Check (Test-Path -LiteralPath (Join-Path $contentRoot 'PatentLabel.lsp')) 'uninstall-retains-files'
    Install-PatentLabel $doc | Out-Null
    Check (Test-Path -LiteralPath $manifestPath) 'reinstall-reenables-disabled-package'
    $doc.Vars['APPAUTOLOAD'] = 15
    Uninstall-PatentLabel $doc | Out-Null
    Check ($doc.Vars['APPAUTOLOAD'] -eq 15) 'uninstall-preserves-autoload-changed-by-user'

    $env:APPDATA = Join-Path $testRoot 'AlreadyTrusted'
    . (Join-Path $PackageDirectory 'Install.ps1') -LibraryOnly
    $doc = FakeDocument ('C:\Existing;' + $contentRoot) 14
    Install-PatentLabel $doc | Out-Null
    Check (-not (Read-InstallState).AddedTrustedPath) 'records-existing-trust-ownership'
    Uninstall-PatentLabel $doc | Out-Null
    Check ($doc.Vars['TRUSTEDPATHS'] -eq ('C:\Existing;' + $contentRoot)) 'uninstall-keeps-preexisting-plugin-trust'
    Check ($doc.Vars['APPAUTOLOAD'] -eq 14) 'uninstall-keeps-preexisting-startup-bit'

    if ($Year -eq 2019) {
    function Get-RunningCadApp([string]$ProgId) {
        if ($script:fakeRunningApps.ContainsKey($ProgId)) { return $script:fakeRunningApps[$ProgId] }
        throw 'Not running'
    }
    $targetDoc = FakeDocument 'D:\Untouched' 12
    $app2019 = New-Object PSObject -Property @{Version='23.0s'; ActiveDocument=$targetDoc}
    $app2020 = New-Object PSObject -Property @{Version='23.1s'; ActiveDocument=(FakeDocument 'D:\Other' 12)}
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
    Check ($targetDoc.Vars['TRUSTEDPATHS'] -eq 'D:\Untouched') 'version-detection-does-not-change-profile'

    }
    if ($Year -eq 2026) {
        $env:APPDATA = Join-Path $testRoot 'Legacy2026Json'
        . (Join-Path $PackageDirectory 'Install.ps1') -LibraryOnly
        New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PackageDirectory 'PatentLabel.bundle/PackageContents.xml') -Destination $manifestPath
        $legacy = @{ProductCode=$productCode;Bundle=$bundleRoot;Status='installed';Version='0.2.4';InstalledAt='2026-01-01';AutoLoadBefore=12;StartupWasEnabled=$false;AddedTrustedPath=$true}
        $legacy | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bundleRoot 'install-state.json') -Encoding UTF8
        $doc = FakeDocument ('D:\Original;' + $contentRoot) 14
        Install-PatentLabel $doc | Out-Null
        Check ((Read-InstallState).AutoLoadBefore -eq 12) 'migrates-original-json-startup-ownership'
        Uninstall-PatentLabel $doc | Out-Null
        Check ($doc.Vars['TRUSTEDPATHS'] -eq 'D:\Original' -and $doc.Vars['APPAUTOLOAD'] -eq 12) 'uninstall-preserves-original-json-restoration'
    }

    $env:APPDATA = Join-Path $testRoot 'ForeignOwner'
    . (Join-Path $PackageDirectory 'Install.ps1') -LibraryOnly
    New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
    [IO.File]::WriteAllText($manifestPath, '<ApplicationPackage ProductCode="OTHER" />')
    $doc = FakeDocument 'D:\Unchanged' 12
    $rejected = $false
    try { Install-PatentLabel $doc | Out-Null } catch { $rejected = $true }
    Check $rejected 'rejects-foreign-bundle'
    Check ($doc.Vars['TRUSTEDPATHS'] -eq 'D:\Unchanged' -and $doc.Vars['APPAUTOLOAD'] -eq 12) 'foreign-owner-rejection-leaves-configuration-unchanged'
    Check ([IO.File]::ReadAllText($manifestPath) -eq '<ApplicationPackage ProductCode="OTHER" />') 'foreign-manifest-preserved'
}
finally {
    $env:APPDATA = $originalAppData
    $report = @{checks=@($checks.ToArray()); passed=@($checks | Where-Object {$_.passed}).Count; failed=@($checks | Where-Object {-not $_.passed}).Count; live_cad_connected=$false; gui_profile_modified=$false}
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $testRoot 'report.json') -Encoding UTF8
    Write-Output ('Installer checks: ' + $report.passed + ' passed, ' + $report.failed + ' failed')
    Write-Output ('Report: ' + (Join-Path $testRoot 'report.json'))
}
