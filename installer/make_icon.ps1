<#
.SYNOPSIS
    Generates windows\runner\resources\app_icon.ico from a square PNG.

.DESCRIPTION
    Produces a multi-resolution Windows .ico (16/24/32/48/64/128/256 px) using
    classic 32-bit BMP/DIB frames (BGRA + AND mask) — the most widely compatible
    icon format, identical in structure to Flutter's default app_icon.ico. This
    avoids PNG-compressed icon entries, which some Windows shell/cache paths
    render incorrectly. Transparency is preserved via the alpha channel.

.PARAMETER Source
    Path to the source PNG (square recommended). Defaults to assets\shop+.png.
#>
param(
    [string]$Source = (Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\shop+.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$RepoRoot = Split-Path $PSScriptRoot -Parent
$OutIco   = Join-Path $RepoRoot 'windows\runner\resources\app_icon.ico'
$sizes    = @(16, 24, 32, 48, 64, 128, 256)

if (-not (Test-Path $Source)) { throw "Source PNG not found: $Source" }

# Returns the raw bytes of one DIB icon image (BITMAPINFOHEADER + BGRA + AND mask).
function New-DibImage([System.Drawing.Bitmap]$bmp, [int]$size) {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $locked = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $locked.Stride
    $top = New-Object byte[] ($stride * $size)   # top-down BGRA rows
    [System.Runtime.InteropServices.Marshal]::Copy($locked.Scan0, $top, 0, $top.Length)
    $bmp.UnlockBits($locked)

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    # BITMAPINFOHEADER (40 bytes). Height is doubled: XOR image + AND mask.
    $bw.Write([UInt32]40)            # biSize
    $bw.Write([Int32]$size)          # biWidth
    $bw.Write([Int32]($size * 2))    # biHeight (XOR + AND)
    $bw.Write([UInt16]1)             # biPlanes
    $bw.Write([UInt16]32)            # biBitCount
    $bw.Write([UInt32]0)             # biCompression = BI_RGB
    $bw.Write([UInt32]0)             # biSizeImage
    $bw.Write([Int32]0)              # biXPelsPerMeter
    $bw.Write([Int32]0)              # biYPelsPerMeter
    $bw.Write([UInt32]0)             # biClrUsed
    $bw.Write([UInt32]0)             # biClrImportant

    # XOR bitmap: 32bpp BGRA, bottom-up.
    for ($y = $size - 1; $y -ge 0; $y--) {
        $bw.Write($top, $y * $stride, $size * 4)
    }

    # AND mask: 1bpp, bottom-up, rows padded to 4 bytes. All zero (alpha handles
    # transparency), which is the standard for 32-bit icons.
    $maskRow = [Math]::Floor(($size + 31) / 32) * 4
    $zeros = New-Object byte[] $maskRow
    for ($y = 0; $y -lt $size; $y++) { $bw.Write($zeros, 0, $maskRow) }

    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()
    return ,$bytes
}

$src = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
$frames = @()
try {
    # Pad to square (transparent) so non-square sources are not stretched.
    $side = [Math]::Max($src.Width, $src.Height)
    $square = New-Object System.Drawing.Bitmap($side, $side, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($square)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($src, [int](($side - $src.Width) / 2), [int](($side - $src.Height) / 2), $src.Width, $src.Height)
    $g.Dispose()

    foreach ($s in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gg = [System.Drawing.Graphics]::FromImage($bmp)
        $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gg.PixelOffsetMode  = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $gg.SmoothingMode    = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $gg.DrawImage($square, 0, 0, $s, $s)
        $gg.Dispose()
        $frames += , (New-DibImage $bmp $s)
        $bmp.Dispose()
    }
    $square.Dispose()
}
finally {
    $src.Dispose()
}

# ── Assemble the .ico container ─────────────────────────────────────────────
$out = New-Object System.IO.MemoryStream
$bw  = New-Object System.IO.BinaryWriter($out)

$bw.Write([UInt16]0)                # reserved
$bw.Write([UInt16]1)                # type = icon
$bw.Write([UInt16]$sizes.Count)     # image count

$offset = 6 + (16 * $sizes.Count)
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s    = $sizes[$i]
    $blob = $frames[$i]
    $dim  = if ($s -ge 256) { 0 } else { $s }   # 0 encodes 256
    $bw.Write([Byte]$dim)           # width
    $bw.Write([Byte]$dim)           # height
    $bw.Write([Byte]0)              # palette count
    $bw.Write([Byte]0)              # reserved
    $bw.Write([UInt16]1)            # color planes
    $bw.Write([UInt16]32)           # bits per pixel
    $bw.Write([UInt32]$blob.Length) # bytes in resource
    $bw.Write([UInt32]$offset)      # offset
    $offset += $blob.Length
}
foreach ($blob in $frames) { $bw.Write($blob) }

$bw.Flush()
[System.IO.File]::WriteAllBytes($OutIco, $out.ToArray())
$bw.Dispose(); $out.Dispose()

Write-Host "Icon written: $OutIco ($([Math]::Round((Get-Item $OutIco).Length/1KB,1)) KB, DIB sizes: $($sizes -join ','))" -ForegroundColor Green
