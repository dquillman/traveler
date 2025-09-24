# Finishes menu URL patterns without using -replace (which choked).
param(
  [string]$UrlsPath = "stays\urls.py"
)

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if(!(Test-Path $UrlsPath)){
  Write-Error "Not found: $UrlsPath"
  exit 1
}

# Read
$text = Get-Content $UrlsPath -Raw
$orig = $text

# Ensure import
if($text -notmatch 'from\s+\.\s+import\s+views'){
  if($text -match 'from\s+django\.urls\s+import\s+path'){
    $text = $text -replace '(from\s+django\.urls\s+import\s+path[^\n]*\n)', '$0' + "from . import views`r`n"
  } else {
    $text = "from django.urls import path`r`nfrom . import views`r`n" + $text
  }
}

# Make sure urlpatterns exists
if($text -notmatch 'urlpatterns\s*='){
  $text += "`r`nurlpatterns = []`r`n"
}

# Insert wanted routes exactly once
$wanted = @(
  'path("charts/", views.stays_charts, name="stays_charts")',
  'path("import/", views.stays_import, name="stays_import")',
  'path("export/", views.stays_export, name="stays_export")'
)

# Locate the urlpatterns block
$match = [regex]::Match($text, 'urlpatterns\s*=\s*\[(.*?)\]', [Text.RegularExpressions.RegexOptions]::Singleline)
if($match.Success){
  $inside = $match.Groups[1].Value
  foreach($w in $wanted){
    if($inside -notmatch [regex]::Escape($w)){
      $inside = $inside.TrimEnd() + "`r`n    $w,"
    }
  }
  $newBlock = "urlpatterns = [" + "`r`n" + $inside.TrimEnd() + "`r`n" + "]"
  $text = $text.Substring(0, $match.Index) + $newBlock + $text.Substring($match.Index + $match.Length)
} else {
  # Fallback: append entries (valid Python)
  foreach($w in $wanted){
    if($text -notmatch [regex]::Escape($w)){
      $text += "`r`nurlpatterns += [ $w ]`r`n"
    }
  }
}

# Write if changed
if($text -ne $orig){
  $bak = "$UrlsPath.bak.$stamp"
  Copy-Item $UrlsPath $bak
  [IO.File]::WriteAllText($UrlsPath, $text, [Text.UTF8Encoding]::new($false))
  Write-Host "Updated: $UrlsPath (backup: $bak)"
} else {
  Write-Host "No changes needed: $UrlsPath"
}
