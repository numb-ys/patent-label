[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PackageDirectory)

$ErrorActionPreference = 'Stop'
$originalAppData = $env:APPDATA
$testRoot = Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts\installer2014-' + [guid]::NewGuid().ToString('N'))
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
    $env:APPDATA = Join-Path $testRoot 'AppData[2014]'
    . (Join-Path $PackageDirectory 'Install2014.ps1') -LibraryOnly
    $doc = FakeDocument 'C:\Existing;D:\Other' 12
    Install-PatentLabel2014 $doc | Out-Null
    Check (Test-Path -LiteralPath $manifestPath) 'installs-manifest'
    Check (Test-Path -LiteralPath (Join-Path $contentRoot 'PatentLabel2014.lsp')) 'installs-backend'
    Check (Test-Path -LiteralPath (Join-Path $contentRoot 'PatentLabel.UI2014.0.2.4.2014.dll')) 'installs-versioned-dll'
    Check ($doc.Vars['TRUSTEDPATHS'] -eq ('C:\Existing;D:\Other;' + $contentRoot)) 'appends-only-exact-plugin-trusted-directory'
    Check ($doc.Vars['APPAUTOLOAD'] -eq 14) 'enables-only-startup-bit'
    Check ($doc.Vars['SECURELOAD'] -eq 2) 'preserves-secureload'
    Check ((Read-InstallState).Version -eq '0.2.4.2014') 'records-version'
    Install-PatentLabel2014 $doc | Out-Null
    Check (@($doc.Vars['TRUSTEDPATHS'] -split ';' | Where-Object { $_ -eq $contentRoot }).Count -eq 1) 'reinstall-does-not-duplicate-trusted-directory'
    Check ((Read-InstallState).AutoLoadBefore -eq 12) 'reinstall-preserves-original-startup-state'
    Check (-not (Test-Path -LiteralPath (Join-Path $bundleRoot 'Backups'))) 'identical-reinstall-does-not-create-backups'
    $doc.Vars['TRUSTEDPATHS'] += ';E:\UserAddedLater'
    Uninstall-PatentLabel2014 $doc | Out-Null
    Check (-not (Test-Path -LiteralPath $manifestPath)) 'uninstall-disables-manifest'
    Check ($doc.Vars['TRUSTEDPATHS'] -eq 'C:\Existing;D:\Other;E:\UserAddedLater') 'uninstall-preserves-other-and-later-trusted-paths'
    Check ($doc.Vars['APPAUTOLOAD'] -eq 12) 'uninstall-restores-only-startup-bit'
    Check (Test-Path -LiteralPath (Join-Path $contentRoot 'PatentLabel2014.lsp')) 'uninstall-retains-files'
    Install-PatentLabel2014 $doc | Out-Null
    Check (Test-Path -LiteralPath $manifestPath) 'reinstall-reenables-disabled-package'
    $doc.Vars['APPAUTOLOAD'] = 15
    Uninstall-PatentLabel2014 $doc | Out-Null
    Check ($doc.Vars['APPAUTOLOAD'] -eq 15) 'uninstall-preserves-autoload-changed-by-user'

    $env:APPDATA = Join-Path $testRoot 'AlreadyTrusted'
    . (Join-Path $PackageDirectory 'Install2014.ps1') -LibraryOnly
    $doc = FakeDocument ('C:\Existing;' + $contentRoot) 14
    Install-PatentLabel2014 $doc | Out-Null
    Check (-not (Read-InstallState).AddedTrustedPath) 'records-existing-trust-ownership'
    Uninstall-PatentLabel2014 $doc | Out-Null
    Check ($doc.Vars['TRUSTEDPATHS'] -eq ('C:\Existing;' + $contentRoot)) 'uninstall-keeps-preexisting-plugin-trust'
    Check ($doc.Vars['APPAUTOLOAD'] -eq 14) 'uninstall-keeps-preexisting-startup-bit'

    $env:APPDATA = Join-Path $testRoot 'ForeignOwner'
    . (Join-Path $PackageDirectory 'Install2014.ps1') -LibraryOnly
    New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
    [IO.File]::WriteAllText($manifestPath, '<ApplicationPackage ProductCode="OTHER" />')
    $doc = FakeDocument 'D:\Unchanged' 12
    $rejected = $false
    try { Install-PatentLabel2014 $doc | Out-Null } catch { $rejected = $true }
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
