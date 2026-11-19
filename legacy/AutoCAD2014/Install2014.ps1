[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Status')][string]$Action = 'Install',
    [switch]$LibraryOnly
)

# ASCII, Windows PowerShell 2.0+; no SDK, compiler or admin rights on the target PC.
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$bundleRoot = Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins\PatentLabel2014.bundle'
$contentRoot = Join-Path $bundleRoot 'Contents\Windows'
$manifestPath = Join-Path $bundleRoot 'PackageContents.xml'
$statePath = Join-Path $bundleRoot 'install-state.xml'
$productCode = '{DC15BCC6-A227-43B0-9E47-B1B772FE48ED}'

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
    try { $script:cad = [Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application.19.1') }
    catch {
        try { $script:cad = [Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application') }
        catch { throw 'Open AutoCAD 2014 and any drawing, then run Install2014.cmd again.' }
    }
    $cadVersion = [string](Invoke-CadCall { $script:cad.Version })
    if (-not $cadVersion.StartsWith('19.1')) {
        throw ('AutoCAD 2014 is required (19.1); connected version: ' + $cadVersion)
    }
    try { return (Invoke-CadCall { $script:cad.ActiveDocument }) }
    catch { throw 'Open any drawing in AutoCAD 2014 and finish the current command, then retry.' }
}

function Get-FileDigest([string]$Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)) }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}

function Read-InstallState {
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    [xml]$stateXml = [IO.File]::ReadAllText($statePath)
    $node = $stateXml.PatentLabelInstall
    if ($null -eq $node) { throw 'Invalid PatentLabel2014 installation record.' }
    $record = New-Object PSObject -Property @{
        ProductCode = [string]$node.ProductCode; Bundle = [string]$node.Bundle
        Status = [string]$node.Status; Version = [string]$node.Version
        InstalledAt = [string]$node.InstalledAt
        AutoLoadBefore = [int]$node.AutoLoadBefore
        StartupWasEnabled = [bool]::Parse($node.StartupWasEnabled)
        AddedTrustedPath = [bool]::Parse($node.AddedTrustedPath)
    }
    if ($record.ProductCode -ne $productCode -or $record.Bundle -ne $bundleRoot) {
        throw 'Invalid PatentLabel2014 installation record.'
    }
    return $record
}

function Write-InstallState($Record) {
    $stateXml = New-Object Xml.XmlDocument
    $node = $stateXml.CreateElement('PatentLabelInstall')
    $null = $stateXml.AppendChild($node)
    foreach ($key in @('ProductCode','Bundle','Status','Version','InstalledAt','AutoLoadBefore','StartupWasEnabled','AddedTrustedPath')) {
        $node.SetAttribute($key, [string]$Record.$key)
    }
    $stateXml.Save($statePath)
}

function Assert-OurBundle {
    if (Test-Path -LiteralPath $manifestPath) {
        [xml]$existing = [IO.File]::ReadAllText($manifestPath)
        if ($existing.ApplicationPackage.ProductCode -ne $productCode) { throw 'Another package owns the target folder.' }
    }
    elseif ((Test-Path -LiteralPath $bundleRoot) -and -not (Test-Path -LiteralPath $statePath)) {
        throw 'Existing target folder has no PatentLabel2014 installation record.'
    }
    $null = Read-InstallState
}

function Copy-ChangedFile([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        if ((Get-FileDigest $Source) -eq (Get-FileDigest $Destination)) { return }
        $backupRoot = Join-Path $bundleRoot ('Backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Copy-Item -LiteralPath $Destination -Destination (Join-Path $backupRoot ([IO.Path]::GetFileName($Destination)))
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    # Unblock only the installed package's own copies; SECURELOAD remains unchanged.
    try { [IO.File]::Delete($Destination + ':Zone.Identifier') } catch { }
}

function Get-TrustedWithoutPlugin([string]$Value) {
    $kept = @($Value -split ';' | Where-Object {
        $_.Trim().TrimEnd('\', '/') -ine $contentRoot.TrimEnd('\', '/')
    })
    return ($kept -join ';')
}

function Install-PatentLabel2014($document) {
    Assert-OurBundle
    $sourceBundle = Join-Path $packageRoot 'PatentLabel2014.bundle'
    $sourceManifest = Join-Path $sourceBundle 'PackageContents.xml'
    [xml]$manifest = [IO.File]::ReadAllText($sourceManifest)
    $module = [string]$manifest.ApplicationPackage.Components.ComponentEntry.ModuleName
    if ($manifest.ApplicationPackage.ProductCode -ne $productCode -or
        $module -notmatch '^\./Contents/Windows/PatentLabel\.UI2014\.[0-9.]+\.dll$') {
        throw 'Invalid AutoCAD 2014 package manifest.'
    }
    $moduleName = [IO.Path]::GetFileName($module.Replace('/', '\'))
    $sourceDll = Join-Path $sourceBundle $module
    $sourceLisp = Join-Path $sourceBundle 'Contents\Windows\PatentLabel2014.lsp'
    foreach ($file in @($sourceDll, $sourceLisp)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw ('Missing package file: ' + $file) }
    }
    $trustedBefore = [string](Invoke-CadCall { $document.GetVariable('TRUSTEDPATHS') })
    $autoBefore = [int](Invoke-CadCall { $document.GetVariable('APPAUTOLOAD') })
    $secureBefore = Invoke-CadCall { $document.GetVariable('SECURELOAD') }
    $alreadyTrusted = @($trustedBefore -split ';' | Where-Object {
        $_.Trim().TrimEnd('\', '/') -ieq $contentRoot.TrimEnd('\', '/')
    }).Count -gt 0
    $state = Read-InstallState
    if ($null -eq $state) {
        $state = New-Object PSObject -Property @{
            ProductCode = $productCode; Bundle = $bundleRoot; Status = 'preparing'
            Version = ''; InstalledAt = (Get-Date).ToString('o')
            AutoLoadBefore = $autoBefore; StartupWasEnabled = (($autoBefore -band 2) -ne 0)
            AddedTrustedPath = -not $alreadyTrusted
        }
    }
    New-Item -ItemType Directory -Path $contentRoot -Force | Out-Null
    # Save recovery/uninstall ownership before changing profile settings.
    Write-InstallState $state
    Copy-ChangedFile $sourceDll (Join-Path $contentRoot $moduleName)
    Copy-ChangedFile $sourceLisp (Join-Path $contentRoot 'PatentLabel2014.lsp')
    $trustedAfter = $trustedBefore
    if (-not $alreadyTrusted) {
        if ([string]::IsNullOrEmpty($trustedBefore)) { $trustedAfter = $contentRoot }
        else { $trustedAfter = $trustedBefore.TrimEnd(';') + ';' + $contentRoot }
        Invoke-CadCall { $document.SetVariable('TRUSTEDPATHS', $trustedAfter) } | Out-Null
    }
    if (($autoBefore -band 2) -eq 0) {
        Invoke-CadCall { $document.SetVariable('APPAUTOLOAD', [int16]($autoBefore -bor 2)) } | Out-Null
    }
    $trustedReadback = [string](Invoke-CadCall { $document.GetVariable('TRUSTEDPATHS') })
    $autoReadback = [int](Invoke-CadCall { $document.GetVariable('APPAUTOLOAD') })
    $secureReadback = Invoke-CadCall { $document.GetVariable('SECURELOAD') }
    if ($trustedReadback -ne $trustedAfter -or ($autoReadback -band 2) -eq 0 -or $secureReadback -ne $secureBefore) {
        throw 'CAD configuration readback failed. Finish active commands and run the installer again.'
    }
    # Enable automatic loading only after all files and settings are ready.
    Copy-ChangedFile $sourceManifest $manifestPath
    $state.Version = [string]$manifest.ApplicationPackage.AppVersion
    $state.Status = 'installed'
    Write-InstallState $state
    Write-Output ('Installed: PatentLabel AutoCAD 2014 / ' + $state.Version)
    Write-Output ('Location: ' + $bundleRoot)
    Write-Output 'Restart AutoCAD 2014. Then type BH. Do not reload an older DLL in that session.'
}

function Uninstall-PatentLabel2014($document) {
    Assert-OurBundle
    $state = Read-InstallState
    if ($null -eq $state) { throw 'No PatentLabel2014 installation was found.' }
    if (Test-Path -LiteralPath $manifestPath) {
        Rename-Item -LiteralPath $manifestPath -NewName ('PackageContents.disabled-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.xml')
    }
    $trustedBefore = [string](Invoke-CadCall { $document.GetVariable('TRUSTEDPATHS') })
    if ($state.AddedTrustedPath) {
        $trustedAfter = Get-TrustedWithoutPlugin $trustedBefore
        if ($trustedAfter -ne $trustedBefore) {
            Invoke-CadCall { $document.SetVariable('TRUSTEDPATHS', $trustedAfter) } | Out-Null
        }
    }
    $autoBefore = [int](Invoke-CadCall { $document.GetVariable('APPAUTOLOAD') })
    if (-not $state.StartupWasEnabled -and $autoBefore -eq ([int]$state.AutoLoadBefore -bor 2)) {
        Invoke-CadCall { $document.SetVariable('APPAUTOLOAD', [int16]($autoBefore -band (-bnot 2))) } | Out-Null
    }
    $state.Status = 'disabled'
    Write-InstallState $state
    Write-Output 'Automatic loading disabled. Restart AutoCAD 2014 to unload the DLL. Files and backups retained.'
}

if ($LibraryOnly) { return }
if ($Action -eq 'Status') {
    Write-Output ('Bundle: ' + $bundleRoot)
    Write-Output ('Automatic loading registered: ' + (Test-Path -LiteralPath $manifestPath))
    return
}
Assert-OurBundle
$document = Get-CadDocument
if ($Action -eq 'Install') { Install-PatentLabel2014 $document }
else { Uninstall-PatentLabel2014 $document }
