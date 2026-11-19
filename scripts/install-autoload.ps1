[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Status')][string]$Action = 'Install',
    [switch]$UpdateFilesOnly
)

# ASCII source: also works in Windows PowerShell 5.1 without an encoding dependency.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins'
$bundleRoot = Join-Path $pluginRoot 'PatentLabel.bundle'
$contentRoot = Join-Path $bundleRoot 'Contents\Windows'
$manifestPath = Join-Path $bundleRoot 'PackageContents.xml'
$statePath = Join-Path $bundleRoot 'install-state.json'
$productCode = '{8B0F3B60-D8F1-4C1B-84CE-C24A6025C691}'

function Invoke-CadCall([scriptblock]$Operation) {
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try { return (& $Operation) }
        catch {
            if ($attempt -eq 19 -or $_.Exception.ToString() -notmatch '80010001|RPC_E_CALL_REJECTED') { throw }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Get-CadDocument {
    try { $script:cad = [Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application') }
    catch { throw 'Open any drawing in AutoCAD 2026, then run this one-time installer again.' }
    $cadVersion = Invoke-CadCall { $script:cad.Version }
    if (-not $cadVersion.StartsWith('25.1')) { throw ('This package requires AutoCAD 2026; found ' + $cadVersion) }
    try { return (Invoke-CadCall { $script:cad.ActiveDocument }) }
    catch { throw 'Open any drawing in AutoCAD 2026, then run this one-time installer again.' }
}

function Get-TrustedWithoutPlugin([string]$Value) {
    $kept = @($Value -split ';' | Where-Object {
        $_.Trim().TrimEnd('\', '/') -ine $contentRoot.TrimEnd('\', '/')
    })
    return ($kept -join ';')
}

function Assert-OurBundle {
    if (Test-Path -LiteralPath $manifestPath) {
        [xml]$existing = Get-Content -LiteralPath $manifestPath -Raw
        if ($existing.ApplicationPackage.ProductCode -ne $productCode) {
            throw ('A different package already owns ' + $bundleRoot)
        }
    }
    elseif ((Test-Path -LiteralPath $bundleRoot) -and -not (Test-Path -LiteralPath $statePath)) {
        throw ('Existing folder has no PatentLabel installation record: ' + $bundleRoot)
    }
}

function Copy-ChangedFile([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        if ((Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash) { return }
        $backupDirectory = Join-Path $bundleRoot ('Backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        Copy-Item -LiteralPath $Destination -Destination (Join-Path $backupDirectory ([IO.Path]::GetFileName($Destination)))
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

if ($Action -eq 'Status') {
    $installedDll = Join-Path $contentRoot 'PatentLabel.UI.dll'
    if (Test-Path -LiteralPath $manifestPath) {
        [xml]$installedManifest = Get-Content -LiteralPath $manifestPath -Raw
        $installedDll = Join-Path $bundleRoot $installedManifest.ApplicationPackage.Components.ComponentEntry.ModuleName
    }
    [pscustomobject]@{
        Bundle = $bundleRoot
        Registered = Test-Path -LiteralPath $manifestPath -PathType Leaf
        Dll = Test-Path -LiteralPath $installedDll -PathType Leaf
        Lisp = Test-Path -LiteralPath (Join-Path $contentRoot 'PatentLabel.lsp') -PathType Leaf
    } | ConvertTo-Json
    exit 0
}

Assert-OurBundle
# File-only upgrades leave CAD, recovery dialogs, drawings and profile settings untouched.
# Only an already installed, managed bundle may use this mode.
if ($UpdateFilesOnly) {
    if ($Action -ne 'Install') { throw 'UpdateFilesOnly is valid only for Install.' }
    if (-not (Test-Path -LiteralPath $statePath) -or -not (Test-Path -LiteralPath $manifestPath)) {
        throw 'A first installation requires an open CAD drawing; file-only updates require an existing installation.'
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.ProductCode -ne $productCode -or $state.Bundle -ne $bundleRoot -or $state.Status -ne 'installed') {
        throw 'Invalid or disabled prior installation record.'
    }
    $sourceDll = Join-Path $projectRoot 'src\PatentLabel.UI.dll'
    if (-not (Test-Path -LiteralPath $sourceDll)) {
        $sourceDll = Join-Path $projectRoot 'src\PatentLabel.UI\bin\Release\net8.0-windows\PatentLabel.UI.dll'
    }
    $sourceLisp = Join-Path $projectRoot 'src\PatentLabel.lsp'
    $sourceManifest = Join-Path $projectRoot 'deployment\PackageContents.xml'
    foreach ($sourceFile in @($sourceDll, $sourceLisp, $sourceManifest)) {
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw ('Missing package file: ' + $sourceFile) }
    }
    [xml]$manifest = Get-Content -LiteralPath $sourceManifest -Raw
    $moduleName = [string]$manifest.ApplicationPackage.Components.ComponentEntry.ModuleName
    if ($manifest.ApplicationPackage.ProductCode -ne $productCode -or
        $moduleName -notmatch '^\./Contents/Windows/PatentLabel\.UI\.[0-9.]+\.dll$') { throw 'Invalid source manifest.' }
    $moduleFileName = [IO.Path]::GetFileName($moduleName.Replace('/', '\'))
    Copy-ChangedFile $sourceDll (Join-Path $contentRoot $moduleFileName)
    Copy-ChangedFile $sourceLisp (Join-Path $contentRoot 'PatentLabel.lsp')
    Copy-ChangedFile $sourceManifest $manifestPath
    $state.Version = [string]$manifest.ApplicationPackage.AppVersion
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    [pscustomobject]@{
        Installed = $true; Version = $state.Version; Bundle = $bundleRoot
        ConfigurationChanged = $false; RequiresRestart = $true
    } | ConvertTo-Json
    exit 0
}
$document = Get-CadDocument
$trustedBefore = [string](Invoke-CadCall { $document.GetVariable('TRUSTEDPATHS') })
$autoBefore = [int](Invoke-CadCall { $document.GetVariable('APPAUTOLOAD') })
$secureBefore = Invoke-CadCall { $document.GetVariable('SECURELOAD') }

if ($Action -eq 'Uninstall') {
    if (-not (Test-Path -LiteralPath $statePath)) { throw 'No PatentLabel automatic-loading installation was found.' }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.ProductCode -ne $productCode -or $state.Bundle -ne $bundleRoot) { throw 'Invalid installation record.' }
    # Disable the manifest, retaining all program files and backups. No recursive delete.
    if (Test-Path -LiteralPath $manifestPath) {
        Rename-Item -LiteralPath $manifestPath -NewName ('PackageContents.disabled-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.xml')
    }
    if ($state.AddedTrustedPath) {
        $trustedAfter = Get-TrustedWithoutPlugin $trustedBefore
        if ($trustedAfter -ne $trustedBefore) {
            Invoke-CadCall { $document.SetVariable('TRUSTEDPATHS', $trustedAfter) } | Out-Null
        }
    }
    # Restore the startup bit only if nobody changed the auto-load setting since installation.
    if (-not $state.StartupWasEnabled -and $autoBefore -eq ([int]$state.AutoLoadBefore -bor 2)) {
        Invoke-CadCall { $document.SetVariable('APPAUTOLOAD', [int16]($autoBefore -band (-bnot 2))) } | Out-Null
    }
    $state.Status = 'disabled'
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-Output 'Automatic loading disabled. Restart AutoCAD to unload the current DLL.'
    exit 0
}

$sourceDll = Join-Path $projectRoot 'src\PatentLabel.UI.dll'
if (-not (Test-Path -LiteralPath $sourceDll)) {
    $sourceDll = Join-Path $projectRoot 'src\PatentLabel.UI\bin\Release\net8.0-windows\PatentLabel.UI.dll'
}
$sourceLisp = Join-Path $projectRoot 'src\PatentLabel.lsp'
$sourceManifest = Join-Path $projectRoot 'deployment\PackageContents.xml'
foreach ($sourceFile in @($sourceDll, $sourceLisp, $sourceManifest)) {
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw ('Missing package file: ' + $sourceFile) }
}
[xml]$manifest = Get-Content -LiteralPath $sourceManifest -Raw
if ($manifest.ApplicationPackage.ProductCode -ne $productCode) { throw 'Invalid source manifest.' }
$moduleName = [string]$manifest.ApplicationPackage.Components.ComponentEntry.ModuleName
if ($moduleName -notmatch '^\./Contents/Windows/PatentLabel\.UI\.[0-9.]+\.dll$') { throw 'Invalid versioned module path.' }
$moduleFileName = [IO.Path]::GetFileName($moduleName.Replace('/', '\'))
New-Item -ItemType Directory -Path $contentRoot -Force | Out-Null
# Versioned filenames allow an update while the previous DLL is still loaded.
Copy-ChangedFile $sourceDll (Join-Path $contentRoot $moduleFileName)
Copy-ChangedFile $sourceLisp (Join-Path $contentRoot 'PatentLabel.lsp')

$alreadyTrusted = @($trustedBefore -split ';' | Where-Object {
    $_.Trim().TrimEnd('\', '/') -ieq $contentRoot.TrimEnd('\', '/')
}).Count -gt 0
$trustedAfter = $trustedBefore
if (-not $alreadyTrusted) {
    $trustedAfter = if ([string]::IsNullOrEmpty($trustedBefore)) { $contentRoot } else { $trustedBefore.TrimEnd(';') + ';' + $contentRoot }
    Invoke-CadCall { $document.SetVariable('TRUSTEDPATHS', $trustedAfter) } | Out-Null
}
$autoAfter = $autoBefore -bor 2
if ($autoAfter -ne $autoBefore) {
    Invoke-CadCall { $document.SetVariable('APPAUTOLOAD', [int16]$autoAfter) } | Out-Null
}

if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.ProductCode -ne $productCode -or $state.Bundle -ne $bundleRoot) { throw 'Invalid prior installation record.' }
}
else {
    $state = [pscustomobject]@{
        Schema = 1; ProductCode = $productCode; Bundle = $bundleRoot
        InstalledAt = (Get-Date).ToString('o'); Version = [string]$manifest.ApplicationPackage.AppVersion
        TrustedPathsBefore = $trustedBefore; AutoLoadBefore = $autoBefore
        AddedTrustedPath = -not $alreadyTrusted
        StartupWasEnabled = (($autoBefore -band 2) -ne 0)
        Status = 'installed'
    }
}
$state.Status = 'installed'
$state.Version = [string]$manifest.ApplicationPackage.AppVersion
$state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8

# The manifest is copied last, enabling discovery only after the modules and configuration are ready.
Copy-ChangedFile $sourceManifest $manifestPath
$trustedReadback = [string](Invoke-CadCall { $document.GetVariable('TRUSTEDPATHS') })
$autoReadback = [int](Invoke-CadCall { $document.GetVariable('APPAUTOLOAD') })
$secureReadback = Invoke-CadCall { $document.GetVariable('SECURELOAD') }
if ($trustedReadback -ne $trustedAfter -or ($autoReadback -band 2) -eq 0 -or $secureReadback -ne $secureBefore) {
    throw 'Installation settings could not be verified.'
}
[pscustomobject]@{
    Installed = $true; Bundle = $bundleRoot
    StartupEnabled = (($autoReadback -band 2) -ne 0)
    ExactPluginDirectoryTrusted = $true; SecureLoadUnchanged = $true
    RequiresRestart = $true
} | ConvertTo-Json
