$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$destination = Join-Path $PSScriptRoot 'assets/fonts'
$downloads = Join-Path (Split-Path $PSScriptRoot) '.tools/downloads'

function Install-FontAssets($Archive, $Url, $Entries) {
    $pending = @($Entries | Where-Object {
        $path = Join-Path $destination $_.Name
        !(Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path).Hash -ine $_.Hash
    })
    if (!$pending.Count) { return }

    New-Item -ItemType Directory -Path $destination, $downloads -Force | Out-Null
    $zipPath = Join-Path $downloads $Archive
    if (!(Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        Invoke-WebRequest -Uri $Url -OutFile "$zipPath.partial" -UseBasicParsing -TimeoutSec 180
        Move-Item -LiteralPath "$zipPath.partial" -Destination $zipPath
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($file in $pending) {
            $entry = $zip.GetEntry($file.Entry)
            if (!$entry) { throw "Missing font asset in ${Archive}: $($file.Entry)" }
            $target = Join-Path $destination $file.Name
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, "$target.partial", $true)
            if ((Get-FileHash -LiteralPath "$target.partial").Hash -ine $file.Hash) {
                throw "Unexpected checksum for $($file.Name) in $zipPath"
            }
            Move-Item -LiteralPath "$target.partial" -Destination $target -Force
        }
    } finally {
        $zip.Dispose()
    }
}

Install-FontAssets 'MiSans.zip' 'https://hyperos.mi.com/font-download/MiSans.zip' @(
    @{ Entry = 'MiSans/ttf/MiSans-Regular.ttf'; Name = 'MiSans-Regular.ttf'; Hash = '9c120f0a849bc0aa5048daae2a3c0f6eecd828b5b33fce682a9622833f5feea6' },
    @{ Entry = 'MiSans/ttf/MiSans-Bold.ttf'; Name = 'MiSans-Bold.ttf'; Hash = 'd0c1d327952ed935e86fb78a97a6c182b44f2c2b08777326786b1f8b26d1fe1e' }
)

$sc = 'HarmonyOS Sans/HarmonyOS_Sans_SC'
Install-FontAssets 'HarmonyOS-Sans.zip' 'https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip' @(
    @{ Entry = "$sc/HarmonyOS_Sans_SC_Regular.ttf"; Name = 'HarmonyOS_Sans_SC_Regular.ttf'; Hash = '297b088424be212207df2ce8b98e335468b782aa6b96832af0b8b773d711e2b1' },
    @{ Entry = "$sc/HarmonyOS_Sans_SC_Bold.ttf"; Name = 'HarmonyOS_Sans_SC_Bold.ttf'; Hash = '43a424b85e47fb53a17b3b32026a71801f86f8e022ca6798d186b47d39fa5f01' },
    @{ Entry = "$sc/LICENSE.txt"; Name = 'HarmonyOS-Sans-LICENSE.txt'; Hash = 'b2ffec0e6269ee41c3b5fc0345ab37600b46d66ebea6c9c58ff37f517bdfa164' }
)
