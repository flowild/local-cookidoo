param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2100000000)]
    [int]$BuildNumber,
    [switch]$Upload,
    [switch]$Release,
    [switch]$UseExistingBuild,
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$SignerSha256
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$app = Join-Path $root 'android-app'
$match = Select-String -LiteralPath (Join-Path $root 'app/version.py') -Pattern "^APP_VERSION = '([0-9]+\.[0-9]+\.[0-9]+)'$"
if (-not $match) { throw 'APP_VERSION konnte nicht gelesen werden.' }
$version = $match.Matches[0].Groups[1].Value
$server = '192.168.184.30'
$remote = "root@$server"
$access = Join-Path $root '.local/proxmox/access'
$sshOptions = @(
    '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=12', '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes', '-o', "UserKnownHostsFile=$access/known_hosts",
    '-i', "$access/id_ed25519"
)

if ($Release -and ($SignerSha256 -notmatch '^[a-fA-F0-9]{64}$' -or
    -not (Test-Path -LiteralPath (Join-Path $app 'android/release-signing.properties') -PathType Leaf))) {
    throw 'Für einen Release-Build werden release-signing.properties und der erwartete Signaturfingerabdruck benötigt.'
}

$certificate = Join-Path $app 'assets/rezeptgarten-ca.pem'
if (-not (Test-Path -LiteralPath $certificate -PathType Leaf)) {
    $temporaryCert = "$certificate.download"
    try {
        & scp -q @sshOptions "${remote}:/var/lib/rezeptgarten-ca/Rezeptgarten-CA.crt" $temporaryCert
        if ($LASTEXITCODE -ne 0) { throw 'Öffentliche Rezeptgarten-CA konnte nicht abgerufen werden.' }
        Move-Item -LiteralPath $temporaryCert -Destination $certificate
    } finally {
        if (Test-Path -LiteralPath $temporaryCert) { Remove-Item -LiteralPath $temporaryCert }
    }
}

$wslProject = $app.Replace('\', '/')
$wslPath = wsl -d Ubuntu-24.04 -- wslpath -a $wslProject
if ($LASTEXITCODE -ne 0 -or -not $wslPath) { throw 'Android-Projektpfad in WSL konnte nicht ermittelt werden.' }
$linuxApp = $wslPath.Trim()
$jdk = '/home/flutterdev/android-build-setup/jdk'
$sdk = '/home/flutterdev/android-build-setup/sdk'
$wsl = @('-d', 'Ubuntu-24.04', '--cd', $linuxApp, '--', 'env', "JAVA_HOME=$jdk", "ANDROID_HOME=$sdk", "ANDROID_SDK_ROOT=$sdk")
$mode = if ($Release) { 'release' } else { 'profile' }
$channel = if ($Release) { 'release' } else { 'test' }
$packageId = if ($Release) { 'de.rezeptgarten.rezeptgarten' } else { 'de.rezeptgarten.rezeptgarten.test' }

if (-not $UseExistingBuild) {
    & wsl @wsl bash build-wsl.sh $linuxApp $mode $version $BuildNumber
    if ($LASTEXITCODE -ne 0) { throw 'Flutter-Prüfung oder APK-Build fehlgeschlagen.' }
}

$artifact = "build/app/outputs/flutter-apk/app-$mode.apk"
$apk = Get-Item -LiteralPath (Join-Path $app $artifact)
$buildTools = "$sdk/build-tools/36.0.0"
$signing = (& wsl @wsl "$jdk/bin/java" -jar "$buildTools/lib/apksigner.jar" verify --print-certs $artifact) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'APK-Signatur ist ungültig.' }
if ($SignerSha256 -and $signing -notmatch "(?im)^Signer #1 certificate SHA-256 digest: $SignerSha256\s*$") {
    throw 'Der APK-Signaturfingerabdruck stimmt nicht überein.'
}
$metadata = (& wsl @wsl "$buildTools/aapt" dump badging $artifact) -join "`n"
$packagePattern = "(?m)^package: name='$([regex]::Escape($packageId))' versionCode='$BuildNumber' versionName='$([regex]::Escape($version))'"
if ($LASTEXITCODE -ne 0 -or $metadata -notmatch $packagePattern) {
    throw 'Paket-ID oder APK-Version stimmt nicht überein.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($apk.FullName)
try {
    $abis = @($zip.Entries | Where-Object FullName -Match '^lib/[^/]+/.+\.so$' |
        ForEach-Object { $_.FullName.Split('/')[1] } | Sort-Object -Unique)
    if ($abis.Count -ne 1 -or $abis[0] -ne 'arm64-v8a') { throw 'Unerwartete APK-Architektur.' }
    if (-not $zip.GetEntry('lib/arm64-v8a/libapp.so')) {
        throw 'Der vorab kompilierte Flutter-App-Code fehlt in der APK.'
    }
} finally {
    $zip.Dispose()
}
$checksum = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk.FullName).Hash.ToLowerInvariant()
Write-Output "APK erstellt: $($apk.FullName)"
if (-not $Upload) { return }

$staging = & ssh @sshOptions $remote 'install -d -m 0755 /var/lib/rezeptgarten-downloads && install -d -m 0700 /var/lib/rezeptgarten-downloads/.incoming && mktemp /var/lib/rezeptgarten-downloads/.incoming/apk.XXXXXXXXXX'
if ($LASTEXITCODE -ne 0 -or $staging -cnotmatch '^/var/lib/rezeptgarten-downloads/\.incoming/(apk\.[A-Za-z0-9]{10})$') {
    throw 'Der temporäre Uploadpfad auf dem LXC konnte nicht angelegt werden.'
}
$stagingName = $Matches[1]
try {
    & scp -q @sshOptions $apk.FullName "${remote}:$staging"
    if ($LASTEXITCODE -ne 0) { throw 'APK-Upload fehlgeschlagen.' }
    $publisher = Get-Content -LiteralPath (Join-Path $root 'deploy/publish-android.py') -Raw -Encoding UTF8
    $previousEncoding = $OutputEncoding
    try {
        $OutputEncoding = New-Object System.Text.UTF8Encoding $false
        $file = $publisher | & ssh @sshOptions $remote "python3 - $channel $stagingName $version $BuildNumber $($apk.Length) $checksum"
        if ($LASTEXITCODE -ne 0 -or $file -cnotmatch '^rezeptgarten-[a-z]+-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-f0-9]{12}\.apk$') {
            throw 'Der LXC konnte die APK nicht veröffentlichen.'
        }
    } finally {
        $OutputEncoding = $previousEncoding
    }
} finally {
    & ssh @sshOptions $remote "rm -f -- '$staging'" | Out-Null
}

$downloadPage = if ($Release) { "https://$server/android/" } else { "https://$server/android/test/" }
$download = "$downloadPage$file"
$manifestUrl = "${downloadPage}latest.json"
$verification = Join-Path $apk.DirectoryName "download-$([Guid]::NewGuid()).apk"
try {
    & curl.exe --fail --silent --show-error --ssl-revoke-best-effort --cacert $certificate --output $verification $download
    if ($LASTEXITCODE -ne 0) { throw 'HTTPS-Download konnte nicht geprüft werden.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $verification).Hash -ine $checksum) {
        throw 'Prüfsumme des HTTPS-Downloads stimmt nicht überein.'
    }
    $record = & curl.exe --fail --silent --show-error --ssl-revoke-best-effort --cacert $certificate $manifestUrl
    if ($LASTEXITCODE -ne 0) { throw 'APK-Update-Manifest konnte nicht abgerufen werden.' }
    $manifest = $record | ConvertFrom-Json
    if ($manifest.version -cne $version -or $manifest.versionCode -ne $BuildNumber -or
        $manifest.file -cne $file -or $manifest.size -ne $apk.Length -or $manifest.sha256 -cne $checksum) {
        throw 'APK-Update-Manifest stimmt nicht mit dem veröffentlichten Build überein.'
    }
} finally {
    if (Test-Path -LiteralPath $verification) { Remove-Item -LiteralPath $verification }
}
Write-Output "APK auf LXC 103 bereitgestellt und geprüft: $download"
Write-Output "Downloadseite: $downloadPage"
