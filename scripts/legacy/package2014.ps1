[CmdletBinding()]
param([string]$AutoCAD2014RefDir = '')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$legacyRoot = Join-Path $projectRoot 'legacy\AutoCAD2014'
if ([string]::IsNullOrEmpty($AutoCAD2014RefDir)) {
    $AutoCAD2014RefDir = Join-Path $projectRoot 'artifacts\sdk2014\refs'
}
foreach ($name in @('AcCoreMgd.dll','AcDbMgd.dll','AcMgd.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $AutoCAD2014RefDir $name))) {
        throw 'Supply -AutoCAD2014RefDir with the official AutoCAD 2013/2014 ObjectARX managed reference assemblies.'
    }
}
& py -3 (Join-Path $PSScriptRoot 'prepare-sources.py')
if ($LASTEXITCODE -ne 0) { throw 'Source preparation failed.' }
$project = Join-Path $projectRoot 'src\PatentLabel.UI2014\PatentLabel.UI2014.csproj'
& dotnet build $project -c Release -t:Rebuild --nologo ('-p:AutoCAD2014RefDir=' + $AutoCAD2014RefDir)
if ($LASTEXITCODE -ne 0) { throw 'AutoCAD 2014 module build failed.' }

$stageRoot = Join-Path $projectRoot ('artifacts\package2014-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $stageRoot 'PatentLabel-AutoCAD2014-0.3.1'
$bundle = Join-Path $package 'PatentLabel2014.bundle'
$contents = Join-Path $bundle 'Contents\Windows'
New-Item -ItemType Directory -Path $contents -Force | Out-Null
[xml]$manifest = [IO.File]::ReadAllText((Join-Path $legacyRoot 'PackageContents.xml'))
$moduleName = [IO.Path]::GetFileName($manifest.ApplicationPackage.Components.ComponentEntry.ModuleName.Replace('/', '\'))
Copy-Item -LiteralPath (Join-Path $projectRoot 'src\PatentLabel.UI2014\bin\Release\net40\PatentLabel.UI2014.dll') -Destination (Join-Path $contents $moduleName)
Copy-Item -LiteralPath (Join-Path $legacyRoot 'PatentLabel2014.lsp') -Destination $contents
Copy-Item -LiteralPath (Join-Path $legacyRoot 'PackageContents.xml') -Destination $bundle
foreach ($name in @('Install2014.cmd','Uninstall2014.cmd','Install2014.ps1','README-2014.txt','TEST-2014.txt')) {
    Copy-Item -LiteralPath (Join-Path $legacyRoot $name) -Destination $package
}
# The one-page quick-start is generated separately with the document runtime.
$guideName = ((0x5148,0x770B,0x8FD9,0x91CC | ForEach-Object { [char]$_ }) -join '')
foreach ($extension in @('.pdf','.txt')) {
    $guidePath = Join-Path $legacyRoot ($guideName + $extension)
    if (Test-Path -LiteralPath $guidePath) { Copy-Item -LiteralPath $guidePath -Destination $package }
}
$archiveName = 'PatentLabel-AutoCAD2014-0.3.1-zh-CN.zip'
if ((Test-Path -LiteralPath (Join-Path $legacyRoot ($guideName + '.pdf'))) -and
    (Test-Path -LiteralPath (Join-Path $legacyRoot ($guideName + '.txt')))) {
    $archiveName = 'PatentLabel-AutoCAD2014-0.3.1-zh-CN.zip'
}
$archive = Join-Path (Join-Path $projectRoot 'dist') $archiveName
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $package
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $package
New-Item -ItemType Directory -Path (Split-Path -Parent $archive) -Force | Out-Null
Compress-Archive -LiteralPath $package -DestinationPath $archive -CompressionLevel Optimal -Force
Write-Output ('PackageDirectory: ' + $package)
Write-Output ('Archive: ' + $archive)
