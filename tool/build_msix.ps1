[CmdletBinding()]
param(
  [string]$ReleaseDir,
  [string]$OutputDir = "build/msix",
  [string]$Version,
  [string]$PackageName = $env:MSIX_PACKAGE_NAME,
  [string]$Publisher = $env:MSIX_PUBLISHER,
  [string]$DisplayName = "Retro TV",
  [string]$PublisherDisplayName = "M Zain Ul Abideen",
  [string]$Description = "Retro TV - a retro-styled live TV streaming experience.",
  [string]$BackgroundColor = "#20202A",
  [string]$Architecture = "x64",
  [string]$Executable = "retro_tv.exe",
  [string]$MinVersion = "10.0.19041.0",
  [string]$MaxVersionTested = "10.0.26100.0",
  [string]$CertificatePath = $env:MSIX_CERT_PATH,
  [string]$CertificatePassword = $env:MSIX_CERT_PASSWORD,
  [string]$TimestampUrl = "http://timestamp.digicert.com",
  [string]$MakeAppxPath,
  [string]$SignToolPath,
  [switch]$NoSign,
  [switch]$TrustSelfSignedCertificate
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestTemplate = Join-Path $repoRoot "windows/msix/AppxManifest.xml"
$assetsDir = Join-Path $repoRoot "windows/msix/Assets"

function Get-PubspecVersion {
  $pubspec = Join-Path $repoRoot "pubspec.yaml"
  $match = Select-String -Path $pubspec -Pattern '^version:\s*([0-9]+(?:\.[0-9]+)*)\+([0-9]+)' | Select-Object -First 1
  if (-not $match) { throw "Could not read version from $pubspec" }
  $name = $match.Matches[0].Groups[1].Value
  $code = $match.Matches[0].Groups[2].Value
  return [PSCustomObject]@{ Name = $name; Code = $code }
}

function Resolve-Tool {
  param([string]$Name, [string]$ExplicitPath, [string[]]$SearchRoots, [string]$InstallHint)

  if ($ExplicitPath) {
    if (-not (Test-Path -LiteralPath $ExplicitPath)) { throw "$Name not found at $ExplicitPath" }
    return (Resolve-Path -LiteralPath $ExplicitPath).Path
  }

  $onPath = Get-Command $Name -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }

  foreach ($root in $SearchRoots) {
    if (-not $root) { continue }
    $candidates = Get-ChildItem -Path $root -Filter "$Name.exe" -Recurse -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending
    if ($candidates) { return $candidates[0].FullName }
  }

  throw "$Name was not found. $InstallHint"
}

function ConvertTo-MsixVersion {
  # NOTE: the parameter must not be called $Input - that name collides with
  # PowerShell's automatic $input variable, which silently swallows the value.
  param([string]$VersionString)

  $parts = @($VersionString -split '\.' | Where-Object { $_ -ne '' })
  if ($parts.Count -eq 3) { $parts += "0" }
  if ($parts.Count -ne 4) { throw "MSIX version must have 4 numeric parts, got '$VersionString'" }

  $numbers = @()
  foreach ($part in $parts) {
    if ($part -notmatch '^[0-9]+$') { throw "MSIX version part '$part' is not numeric" }
    $number = [int]$part
    if ($number -gt 65535) { throw "MSIX version part '$part' exceeds 65535" }
    $numbers += $number
  }
  if ($numbers[0] -eq 0) { throw "MSIX major version cannot be 0" }
  if ($numbers[3] -ne 0) { throw "Microsoft Store requires the MSIX revision component to be 0, got '$VersionString'" }
  return ($numbers -join ".")
}

Push-Location $repoRoot
try {
  if (-not $PackageName) { $PackageName = "MZainUlAbideen.RetroTV" }
  if (-not $Publisher) { $Publisher = "CN=1C68AC37-6A07-4F31-846A-C808E6F3934A" }

  $pubspecVersion = Get-PubspecVersion
  if (-not $Version) { $Version = "$($pubspecVersion.Name).0" }
  $msixVersion = ConvertTo-MsixVersion $Version

  if (-not $ReleaseDir) { $ReleaseDir = "build/windows/$Architecture/runner/Release" }
  if (-not (Test-Path -LiteralPath $ReleaseDir)) {
    throw "Release directory '$ReleaseDir' not found. Run: flutter build windows --release"
  }
  $releasePath = (Resolve-Path -LiteralPath $ReleaseDir).Path
  $executablePath = Join-Path $releasePath $Executable
  if (-not (Test-Path -LiteralPath $executablePath)) {
    throw "'$Executable' not found in $releasePath"
  }
  if (-not (Test-Path -LiteralPath $assetsDir)) {
    throw "MSIX assets missing. Run: pwsh -File tool/generate_msix_assets.ps1"
  }

  $outputPath = Join-Path $repoRoot $OutputDir
  $stagingPath = Join-Path $repoRoot "build/msix/staging"
  New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
  if (Test-Path -LiteralPath $stagingPath) { Remove-Item -LiteralPath $stagingPath -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $stagingPath | Out-Null

  Copy-Item -Path (Join-Path $releasePath "*") -Destination $stagingPath -Recurse -Force
  # The destination must exist first: copying a wildcard into a non-existent
  # destination renames the FIRST file to that name instead of creating a folder.
  $stagingAssets = Join-Path $stagingPath "Assets"
  New-Item -ItemType Directory -Force -Path $stagingAssets | Out-Null
  Copy-Item -Path (Join-Path $assetsDir "*") -Destination $stagingAssets -Recurse -Force

  $escaped = @{
    "{{PACKAGE_NAME}}" = [System.Security.SecurityElement]::Escape($PackageName)
    "{{PUBLISHER}}" = [System.Security.SecurityElement]::Escape($Publisher)
    "{{VERSION}}" = $msixVersion
    "{{ARCHITECTURE}}" = $Architecture
    "{{DISPLAY_NAME}}" = [System.Security.SecurityElement]::Escape($DisplayName)
    "{{PUBLISHER_DISPLAY_NAME}}" = [System.Security.SecurityElement]::Escape($PublisherDisplayName)
    "{{DESCRIPTION}}" = [System.Security.SecurityElement]::Escape($Description)
    "{{BACKGROUND_COLOR}}" = $BackgroundColor
    "{{EXECUTABLE}}" = $Executable
    "{{MIN_VERSION}}" = $MinVersion
    "{{MAX_VERSION_TESTED}}" = $MaxVersionTested
  }

  $manifest = Get-Content -LiteralPath $manifestTemplate -Raw
  foreach ($token in $escaped.Keys) { $manifest = $manifest.Replace($token, $escaped[$token]) }
  $renderedManifest = Join-Path $stagingPath "AppxManifest.xml"
  Set-Content -LiteralPath $renderedManifest -Value $manifest -Encoding UTF8
  [xml]$parsed = Get-Content -LiteralPath $renderedManifest -Raw
  Write-Host ("identity: Name={0} Publisher={1} Version={2} Arch={3}" -f $parsed.Package.Identity.Name, $parsed.Package.Identity.Publisher, $parsed.Package.Identity.Version, $parsed.Package.Identity.ProcessorArchitecture)

  $kitsRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
  $makeappx = Resolve-Tool -Name "makeappx" -ExplicitPath $MakeAppxPath -SearchRoots @($kitsRoot, "$env:ProgramFiles\Windows Kits\10\bin") -InstallHint "Install the Windows SDK (winget/choco: windows-sdk-10.0.22621) or pass -MakeAppxPath."

  $packageName = ("{0}-{1}-{2}" -f ($DisplayName -replace '[^A-Za-z0-9]', ''), $msixVersion, $Architecture)
  $finalPackage = Join-Path $outputPath "$packageName.msix"
  if (Test-Path -LiteralPath $finalPackage) { Remove-Item -LiteralPath $finalPackage -Force }

  Write-Host "packing $makeappx"
  & $makeappx pack /d $stagingPath /p $finalPackage /o
  if ($LASTEXITCODE -ne 0) { throw "makeappx pack failed with exit code $LASTEXITCODE" }

  if (-not $NoSign) {
    $signtool = Resolve-Tool -Name "signtool" -ExplicitPath $SignToolPath -SearchRoots @($kitsRoot, "$env:ProgramFiles\Windows Kits\10\bin") -InstallHint "Install the Windows SDK or pass -SignToolPath."
    $tempPfx = $null

    if (-not $CertificatePath) {
      $alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      $passwordBuilder = New-Object System.Text.StringBuilder
      for ($index = 0; $index -lt 32; $index++) {
        $null = $passwordBuilder.Append($alphabet[(Get-Random -Maximum $alphabet.Length)])
      }
      $plainPassword = $passwordBuilder.ToString()
      $securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force
      # NOTE: New-SelfSignedCertificate on Windows PowerShell 5.1 has no
      # -Password parameter, so the export password is applied afterwards by
      # Export-PfxCertificate instead (hence -KeyExportPolicy Exportable).
      $certificate = New-SelfSignedCertificate -Type Custom -KeyUsage DigitalSignature -Subject $Publisher -KeyExportPolicy Exportable -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(2)
      $tempPfx = Join-Path ([System.IO.Path]::GetTempPath()) ("retrotv-{0}.pfx" -f [Guid]::NewGuid().ToString("N"))
      Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($certificate.Thumbprint)" -FilePath $tempPfx -Password $securePassword | Out-Null
      $CertificatePath = $tempPfx
      $CertificatePassword = $plainPassword
      $cerPath = Join-Path $outputPath "$packageName.cer"
      Export-Certificate -Cert "Cert:\CurrentUser\My\$($certificate.Thumbprint)" -FilePath $cerPath | Out-Null
      Write-Host "signed with a generated self-signed certificate (subject $Publisher)"
      Write-Host "certificate for sideload testing: $cerPath"
      if ($TrustSelfSignedCertificate) {
        # Import into the *current user* store: that is what Windows uses to
        # validate an AppX package installed by this user, and it needs no
        # elevation. LocalMachine\TrustedPeople is the wrong target here -
        # it fails without admin rights, and Import-Certificate reports that
        # as a non-terminating error, so the failure used to pass silently and
        # left the package untrusted.
        try {
          Import-Certificate -FilePath $cerPath `
            -CertStoreLocation "Cert:\CurrentUser\TrustedPeople" `
            -ErrorAction Stop | Out-Null
          Write-Host "certificate trusted in CurrentUser\TrustedPeople (no admin rights needed)"
        } catch {
          Write-Warning "could not trust the certificate automatically: $($_.Exception.Message)"
          Write-Host "run this by hand to install it:"
          Write-Host "  Import-Certificate -FilePath `"$cerPath`" -CertStoreLocation Cert:\CurrentUser\TrustedPeople"
        }
      }
    }

    $signArgs = @("sign", "/fd", "SHA256", "/f", $CertificatePath, "/p", $CertificatePassword)
    if ($TimestampUrl) { $signArgs += @("/tr", $TimestampUrl, "/td", "SHA256") }
    $signArgs += $finalPackage
    & $signtool @signArgs
    if ($LASTEXITCODE -ne 0) { throw "signtool failed with exit code $LASTEXITCODE" }

    if ($tempPfx -and (Test-Path -LiteralPath $tempPfx)) { Remove-Item -LiteralPath $tempPfx -Force }
  }

  Write-Host ""
  Write-Host "MSIX package: $finalPackage"
  Write-Host ("size: {0:N2} MB" -f ((Get-Item -LiteralPath $finalPackage).Length / 1MB))
  Write-Host ""
  Write-Host "Partner Center identity (must match your reservation exactly):"
  Write-Host "  Name      = $PackageName"
  Write-Host "  Publisher = $Publisher"
  Write-Host "  Version   = $msixVersion"
}
finally {
  Pop-Location
}
