[CmdletBinding()]
param(
  [string]$Source = "web/icons/Icon-512.png",
  [string]$OutputDir = "windows/msix/Assets",
  [string]$Background = "#20202A"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
  $sourcePath = Join-Path $repoRoot $Source
  if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Source logo not found: $sourcePath"
  }

  $outPath = Join-Path $repoRoot $OutputDir
  New-Item -ItemType Directory -Force -Path $outPath | Out-Null

  $backgroundColor = [System.Drawing.ColorTranslator]::FromHtml($Background)
  $logo = [System.Drawing.Image]::FromFile($sourcePath)

  $targets = @(
    @{ Name = "StoreLogo.png"; Mode = "fill"; Width = 50; Height = 50; Icon = 0 },
    @{ Name = "Square44x44Logo.png"; Mode = "fill"; Width = 44; Height = 44; Icon = 0 },
    @{ Name = "SmallTileLogo.png"; Mode = "fill"; Width = 71; Height = 71; Icon = 0 },
    @{ Name = "Square150x150Logo.png"; Mode = "fill"; Width = 150; Height = 150; Icon = 0 },
    @{ Name = "Square310x310Logo.png"; Mode = "fill"; Width = 310; Height = 310; Icon = 0 },
    @{ Name = "LockScreenLogoBadge.png"; Mode = "fill"; Width = 24; Height = 24; Icon = 0 },
    @{ Name = "Wide310x150Logo.png"; Mode = "center"; Width = 310; Height = 150; Icon = 110 },
    @{ Name = "SplashScreen.png"; Mode = "center"; Width = 620; Height = 300; Icon = 180 }
  )

  foreach ($target in $targets) {
    $bitmap = New-Object System.Drawing.Bitmap $target.Width, $target.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $brush = [System.Drawing.SolidBrush]::new($backgroundColor)
    $graphics.FillRectangle($brush, 0, 0, $target.Width, $target.Height)

    if ($target.Mode -eq "fill") {
      $graphics.DrawImage($logo, 0, 0, $target.Width, $target.Height)
    } else {
      $iconSize = [int]$target.Icon
      $offsetX = [int](($target.Width - $iconSize) / 2)
      $offsetY = [int](($target.Height - $iconSize) / 2)
      $graphics.DrawImage($logo, $offsetX, $offsetY, $iconSize, $iconSize)
    }

    $file = Join-Path $outPath $target.Name
    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("msix-asset-{0}.png" -f [Guid]::NewGuid().ToString("N"))
    $bitmap.Save($tempFile, [System.Drawing.Imaging.ImageFormat]::Png)
    [System.IO.File]::Copy($tempFile, "\\?\$file", $true)
    Remove-Item -LiteralPath $tempFile -Force
    $brush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
    Write-Host ("wrote {0} ({1}x{2})" -f $file, $target.Width, $target.Height)
  }

  $logo.Dispose()
  Write-Host ("generated {0} MSIX logo assets from {1}" -f $targets.Count, $Source)
}
finally {
  Pop-Location
}
