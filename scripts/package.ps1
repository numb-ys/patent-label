[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'src\PatentLabel.lsp'
$readmePath = Join-Path $projectRoot 'docs\README.zh-CN.md'
$uiProject = Join-Path $projectRoot 'src\PatentLabel.UI\PatentLabel.UI.csproj'
$checklistName = ((0x8BD5, 0x7528, 0x68C0, 0x67E5 | ForEach-Object { [char]$_ }) -join '') + '.md'
$checklistPath = Join-Path $projectRoot ('docs\' + $checklistName)

& dotnet build $uiProject -c Release -t:Rebuild --nologo
if ($LASTEXITCODE -ne 0) { throw 'UI module build failed; package was not created.' }
$uiDllPath = Join-Path $projectRoot 'src\PatentLabel.UI\bin\Release\net8.0-windows\PatentLabel.UI.dll'

foreach ($requiredPath in @($sourcePath, $readmePath, $uiDllPath, $checklistPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required package file is missing: $requiredPath"
    }
}

$outputDirectory = Join-Path $projectRoot 'dist'
$archivePath = Join-Path $outputDirectory 'PatentLabel-AutoCAD2026-0.4.0-zh-CN.zip'
$stagingDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('PatentLabel-package-' + [guid]::NewGuid().ToString('N'))
$packageDirectory = Join-Path $stagingDirectory 'PatentLabel-0.4.0'
$packageSourceDirectory = Join-Path $packageDirectory 'src'
$packageScriptsDirectory = Join-Path $packageDirectory 'scripts'
$packageDeploymentDirectory = Join-Path $packageDirectory 'deployment'

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $packageSourceDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $packageScriptsDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $packageDeploymentDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $packageSourceDirectory 'PatentLabel.lsp')
Copy-Item -LiteralPath $uiDllPath -Destination (Join-Path $packageSourceDirectory 'PatentLabel.UI.dll')
Copy-Item -LiteralPath $readmePath -Destination (Join-Path $packageDirectory 'README.md')
Copy-Item -LiteralPath $checklistPath -Destination (Join-Path $packageDirectory $checklistName)
Copy-Item -LiteralPath (Join-Path $projectRoot 'Install-AutoLoad.cmd') -Destination $packageDirectory
Copy-Item -LiteralPath (Join-Path $projectRoot 'Uninstall-AutoLoad.cmd') -Destination $packageDirectory
Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\install-autoload.ps1') -Destination $packageScriptsDirectory
Copy-Item -LiteralPath (Join-Path $projectRoot 'deployment\PackageContents.xml') -Destination $packageDeploymentDirectory
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $packageDirectory
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $packageDirectory
Compress-Archive -LiteralPath $packageDirectory -DestinationPath $archivePath -CompressionLevel Optimal -Force

# Keep the uniquely named staging directory; no recursive deletion is performed.
Write-Output $archivePath
