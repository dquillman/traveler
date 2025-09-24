param(
  [string]$ConfigUrls = "G:\users\daveq\traveler\config\urls.py"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ConfigUrls)) {
  throw "config/urls.py not found at: $ConfigUrls"
}

$orig = Get-Content -Raw -LiteralPath $ConfigUrls
$bak  = "$ConfigUrls.bak"

# Comment out any lines that define custom error handlers (handler404/500/403/400)
$lines = $orig -split "(`r`n|`n|`r)"
for ($i=0; $i -lt $lines.Length; $i++) {
  if ($lines[$i] -match '^\s*handler(404|500|403|400)\s*=') {
    if ($lines[$i] -notmatch '^\s*#') {
      $lines[$i] = "# " + $lines[$i]
    }
  }
}
$new = [string]::Join("`r`n", $lines)

if ($new -ne $orig) {
  Set-Content -NoNewline -LiteralPath $bak -Value $orig
  Set-Content -NoNewline -LiteralPath $ConfigUrls -Value $new
  Write-Host "Commented out custom error handlers. Backup at $bak"
} else {
  Write-Host "No custom error handler lines found or already commented."
}

Write-Host "Done. Try: python manage.py runserver"
