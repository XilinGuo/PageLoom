param(
    [Parameter(Mandatory = $true)][string]$Flutter,
    [Parameter(Mandatory = $true)][string]$EngineDirectory,
    [Parameter(Mandatory = $true)][string]$VCRedistX64
)

$ErrorActionPreference = 'Stop'
$Flutter = (Resolve-Path -LiteralPath $Flutter).Path
$EngineDirectory = (Resolve-Path -LiteralPath $EngineDirectory).Path
$VCRedistX64 = (Resolve-Path -LiteralPath $VCRedistX64).Path
$repo = Split-Path $PSScriptRoot
$asset = @(Get-ChildItem -LiteralPath $EngineDirectory -Filter 'offline_assets_*.zip')
if ($asset.Count -ne 1 -or !(Test-Path "$EngineDirectory/runtime/pythonw.exe")) {
    throw 'Use the extracted official v2.9.0 / BabelDOC v0.6.4 Windows x64 release with assets.'
}
$crt = Join-Path $VCRedistX64 'Microsoft.VC143.CRT'
if (!(Test-Path "$crt/msvcp140.dll")) {
    throw 'Provide the x64 directory of the Visual Studio 2022 MSVC redistributables.'
}

& (Join-Path $PSScriptRoot 'fetch-fonts.ps1')
Push-Location $PSScriptRoot
try {
    & $Flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
} finally {
    Pop-Location
}

$release = Join-Path $PSScriptRoot 'build/windows/x64/runner/Release'
$dist = Join-Path $repo 'dist'
$bundle = Join-Path $dist 'PDFMathTranslate-Windows-x64'
if (Test-Path -LiteralPath $bundle) {
    throw "Move the existing bundle before packaging: $bundle"
}
New-Item -ItemType Directory -Path $dist -Force | Out-Null
# Publish the finished directory only after the runtime check succeeds.
$staging = Join-Path $dist ('staging-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$staging/engine" -Force | Out-Null

function Copy-Tree($From, $To) {
    & robocopy.exe $From $To /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 /XD __pycache__
    if ($LASTEXITCODE -ge 8) { throw "Copy failed: $From" }
}

Copy-Tree $release $staging
Copy-Tree "$EngineDirectory/runtime" "$staging/engine/runtime"
Copy-Tree "$EngineDirectory/site-packages" "$staging/engine/site-packages"
Copy-Tree "$repo/pdf2zh_next" "$staging/engine/site-packages/pdf2zh_next"
Copy-Item -LiteralPath $asset[0].FullName -Destination "$staging/engine"
Copy-Item -LiteralPath "$PSScriptRoot/backend/bridge.py" -Destination "$staging/engine"
Copy-Item -LiteralPath "$repo/LICENSE", "$PSScriptRoot/README.md" -Destination $staging

$pythonPath = Get-ChildItem -LiteralPath "$staging/engine/runtime" -Filter 'python*._pth'
if (@($pythonPath).Count -ne 1) { throw 'Expected one embedded Python path file.' }
Set-Content -LiteralPath $pythonPath.FullName -Value ($pythonPath.BaseName + '.zip'), '.', '..\site-packages' -Encoding ascii

$redist = @($crt, (Join-Path $VCRedistX64 'Microsoft.VC143.OpenMP'))
foreach ($folder in $redist) {
    foreach ($dll in (Get-ChildItem -LiteralPath $folder -Filter '*.dll')) {
        Copy-Item -LiteralPath $dll.FullName -Destination $staging
        Copy-Item -LiteralPath $dll.FullName -Destination "$staging/engine/runtime"
    }
}

& "$staging/engine/runtime/python.exe" "$staging/engine/bridge.py" --check
if ($LASTEXITCODE -ne 0) { throw 'Packaged runtime check failed.' }
$schema = "$staging/engine/settings-schema.json"
& "$staging/engine/runtime/python.exe" "$staging/engine/bridge.py" --schema $schema
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $schema)) {
    throw 'Could not generate the packaged settings schema.'
}
Rename-Item -LiteralPath $staging -NewName (Split-Path $bundle -Leaf)
Write-Host $bundle
