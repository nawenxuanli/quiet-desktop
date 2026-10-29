param([string]$BuildDirectory = 'windows-build')
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    foreach ($name in @('QUIET_STORE_PACKAGE_NAME', 'QUIET_STORE_PUBLISHER', 'QUIET_STORE_PUBLISHER_DISPLAY_NAME')) {
        if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Missing required Partner Center identity setting: $name" }
    }
    $root = [IO.Path]::GetFullPath($BuildDirectory)
    $staging = Join-Path $root 'msix-staging'
    New-Item -ItemType Directory -Force $staging | Out-Null
    Copy-Item (Join-Path $root 'app\*') $staging -Recurse -Force
    New-Item -ItemType Directory -Force (Join-Path $staging 'StoreAssets') | Out-Null
    foreach ($name in @('Square44x44Logo.png', 'Square150x150Logo.png', 'StoreLogo.png')) { Copy-Item ('Windows' + $name) (Join-Path $staging ('StoreAssets\' + $name)) }
    function XmlEscape([string]$s) { [Security.SecurityElement]::Escape($s) }
    $packageName = XmlEscape $env:QUIET_STORE_PACKAGE_NAME
    $publisher = XmlEscape $env:QUIET_STORE_PUBLISHER
    $publisherDisplayName = XmlEscape $env:QUIET_STORE_PUBLISHER_DISPLAY_NAME
    $manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10" xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities" IgnorableNamespaces="uap rescap">
  <Identity Name="$packageName" Publisher="$publisher" Version="1.6.0.0" ProcessorArchitecture="x64" />
  <Properties><DisplayName>Quiet Desktop</DisplayName><PublisherDisplayName>$publisherDisplayName</PublisherDisplayName><Logo>StoreAssets\StoreLogo.png</Logo><Description>A calm desktop companion with app shortcuts, photos, and local notes.</Description></Properties>
  <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" /></Dependencies>
  <Resources><Resource Language="en-US" /></Resources>
  <Applications><Application Id="QuietDesktop" Executable="QuietDesktop.exe" EntryPoint="Windows.FullTrustApplication"><uap:VisualElements DisplayName="Quiet Desktop" Description="Your apps, photos, and notes within reach." BackgroundColor="transparent" Square44x44Logo="StoreAssets\Square44x44Logo.png" Square150x150Logo="StoreAssets\Square150x150Logo.png" /></Application></Applications>
  <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
"@
    $manifest | Set-Content -Encoding utf8 (Join-Path $staging 'AppxManifest.xml')
    $sdk = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Directory | Sort-Object Name -Descending | Where-Object { Test-Path (Join-Path $_.FullName 'x64\makeappx.exe') } | Select-Object -First 1
    if (-not $sdk) { throw 'Windows SDK packaging tools not found.' }
    $makeappx = Join-Path $sdk.FullName 'x64\makeappx.exe'
    & $makeappx pack /d $staging /p (Join-Path $root 'Quiet-Desktop-1.6.0.0-x64.msix') /o | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'MSIX packaging failed.' }
    # A separate signed copy is used only for certification checks on this disposable runner.
    $testPackage = Join-Path $root 'certification-test.msix'
    Copy-Item (Join-Path $root 'Quiet-Desktop-1.6.0.0-x64.msix') $testPackage
    $certificate = New-SelfSignedCertificate -Type Custom -Subject $env:QUIET_STORE_PUBLISHER -KeyUsage DigitalSignature -FriendlyName 'Quiet Desktop CI test only' -CertStoreLocation 'Cert:\CurrentUser\My' -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
    & (Join-Path $sdk.FullName 'x64\signtool.exe') sign /fd SHA256 /sha1 $certificate.Thumbprint $testPackage | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Certification test signing failed.' }
    $wack = 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe'
    if (-not (Test-Path $wack)) { throw 'Windows App Certification Kit not installed on this runner.' }
    & $wack reset | Out-Null
    & $wack test -appxpackagepath $testPackage -reportoutputpath (Join-Path $root 'certification-report.xml') | Out-Null
    $exitCode = $LASTEXITCODE
    Remove-Item $testPackage -Force
    if ($exitCode -ne 0) { throw 'Windows App Certification Kit reported a failure. Review certification-report.xml before submission.' }
} finally { Pop-Location }
