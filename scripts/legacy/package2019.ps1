[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$legacyRoot = Join-Path $projectRoot 'legacy\AutoCAD2019'
& py -3 (Join-Path $PSScriptRoot 'prepare2019.py')
if ($LASTEXITCODE -ne 0) { throw 'AutoCAD 2019 source preparation failed.' }
$project = Join-Path $projectRoot 'src\PatentLabel.UI2019\PatentLabel.UI2019.csproj'
& dotnet build $project -c Release -t:Rebuild --nologo
if ($LASTEXITCODE -ne 0) { throw 'AutoCAD 2019 module build failed.' }

$stageRoot = Join-Path $projectRoot ('artifacts\package2019-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $stageRoot 'PatentLabel-AutoCAD2019-0.3.2'
$bundle = Join-Path $package 'PatentLabel2019.bundle'
$contents = Join-Path $bundle 'Contents\Windows'
New-Item -ItemType Directory -Path $contents -Force | Out-Null
[xml]$manifest = [IO.File]::ReadAllText((Join-Path $legacyRoot 'PackageContents.xml'))
$moduleName = [IO.Path]::GetFileName($manifest.ApplicationPackage.Components.ComponentEntry.ModuleName.Replace('/', '\'))
Copy-Item -LiteralPath (Join-Path $projectRoot 'src\PatentLabel.UI2019\bin\Release\net47\PatentLabel.UI2019.dll') -Destination (Join-Path $contents $moduleName)
Copy-Item -LiteralPath (Join-Path $legacyRoot 'PatentLabel2019.lsp') -Destination $contents
Copy-Item -LiteralPath (Join-Path $legacyRoot 'PackageContents.xml') -Destination $bundle
foreach ($name in @('Install2019.cmd','Uninstall2019.cmd','Install2019.ps1','README-2019.txt','TEST-2019.txt')) {
    Copy-Item -LiteralPath (Join-Path $legacyRoot $name) -Destination $package
}
$guideName = ((0x5148,0x770B,0x8FD9,0x91CC | ForEach-Object { [char]$_ }) -join '')
foreach ($extension in @('.pdf','.txt')) {
    $guidePath = Join-Path $legacyRoot ($guideName + $extension)
    if (-not (Test-Path -LiteralPath $guidePath)) { throw 'Build the 2019 quick-start PDF and text with create_quickstart2014.py --year 2019 first.' }
    Copy-Item -LiteralPath $guidePath -Destination $package
}
$archive = Join-Path $projectRoot 'dist\PatentLabel-AutoCAD2019-0.3.2-zh-CN.zip'
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $package
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $package
New-Item -ItemType Directory -Path (Split-Path -Parent $archive) -Force | Out-Null
Compress-Archive -LiteralPath $package -DestinationPath $archive -CompressionLevel Optimal -Force
Write-Output ('PackageDirectory: ' + $package)
Write-Output ('Archive: ' + $archive)
