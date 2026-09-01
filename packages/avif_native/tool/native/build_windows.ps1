param(
  [Parameter(Mandatory = $true)][string]$Target,
  [Parameter(Mandatory = $true)][string]$Profile
)
$ErrorActionPreference = 'Stop'
if ($Target -ne 'windows-x64') { throw "Unsupported target: $Target" }

$Root = (Resolve-Path "$PSScriptRoot/../..").Path
$Repo = (Resolve-Path "$Root/../..").Path
$Cache = if ($env:AVIF_NATIVE_CACHE) { $env:AVIF_NATIVE_CACHE } else { "$Repo/.native-cache" }
$Sources = "$Cache/sources"
$Build = "$Cache/build/$Target/$Profile"
$Dist = "$Repo/dist/$Target/$Profile"
$Versions = Get-Content "$Root/native/versions.json" | ConvertFrom-Json

function Checkout-Source([string]$Name) {
  $Info = $Versions.$Name
  $Dir = "$Sources/$Name"
  if (Test-Path "$Dir/.git") {
    $Head = git -C $Dir rev-parse HEAD
    if ($Head -eq $Info.commit) { return }
  }
  Remove-Item -Recurse -Force $Dir -ErrorAction SilentlyContinue
  git clone --quiet --filter=blob:none --no-checkout $Info.repository $Dir
  git -C $Dir fetch --quiet --depth 1 origin $Info.commit
  git -C $Dir checkout --quiet --detach $Info.commit
}

New-Item -ItemType Directory -Force $Sources, $Dist | Out-Null
Checkout-Source 'libavif'
Checkout-Source 'libaom'
Checkout-Source 'dav1d'
Remove-Item -Recurse -Force "$Sources/libavif/ext/aom", "$Sources/libavif/ext/dav1d" -ErrorAction SilentlyContinue
New-Item -ItemType Junction -Path "$Sources/libavif/ext/aom" -Target "$Sources/libaom" | Out-Null
New-Item -ItemType Junction -Path "$Sources/libavif/ext/dav1d" -Target "$Sources/dav1d" | Out-Null

$Dav1dModule = "$Sources/libavif/cmake/Modules/LocalDav1d.cmake"
$Dav1dConfig = [IO.File]::ReadAllText($Dav1dModule)
$Dav1dConfig = $Dav1dConfig.Replace(
  '-Denable_tests=false ${EXTRA_ARGS} <SOURCE_DIR>',
  '-Denable_tests=false -Db_vscrt=mt ${EXTRA_ARGS} <SOURCE_DIR>')
[IO.File]::WriteAllText($Dav1dModule, $Dav1dConfig)

Remove-Item -Recurse -Force $Build -ErrorAction SilentlyContinue
cmake -S "$Root/native" -B $Build -A x64 `
  "-DCMAKE_BUILD_TYPE=MinSizeRel" `
  "-DLIBAVIF_SOURCE_DIR=$Sources/libavif" `
  "-DAVIF_PROFILE=$Profile"
cmake --build $Build --config MinSizeRel --target avif_native --parallel

$Library = Get-ChildItem $Build -Recurse -Filter avif_native.dll | Select-Object -First 1
if (-not $Library) { throw 'Built library not found' }
Copy-Item $Library.FullName "$Dist/avif_native.dll"

$Input = [IO.File]::OpenRead("$Dist/avif_native.dll")
$Output = [IO.File]::Create("$Dist/avif_native.dll.gz")
$Gzip = [IO.Compression.GZipStream]::new($Output, [IO.Compression.CompressionLevel]::SmallestSize)
try { $Input.CopyTo($Gzip) } finally { $Gzip.Dispose(); $Output.Dispose(); $Input.Dispose() }
Write-Output "$Dist/avif_native.dll"
