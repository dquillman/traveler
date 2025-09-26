# safe_delete_everywhere.ps1
# Adds confirmation prompts to Delete actions across ALL Django templates.
# Backs up each modified file with .bak.YYYYMMDD_HHMMSS suffix.

param(
  [string]$Root = "G:\users\daveq\traveler",
  [string]$TemplatesSubdir = "templates",
  [string]$ConfirmText = "Are you sure you want to delete this item?"
)

$ErrorActionPreference = "Stop"

$templatesPath = Join-Path $Root $TemplatesSubdir
if (-not (Test-Path $templatesPath)) {
  Write-Host "❌ Templates folder not found: $templatesPath" -ForegroundColor Red
  exit 1
}

# Get *.html files under templates (recursive)
$files = Get-ChildItem -Path $templatesPath -Filter *.html -Recurse -File
if (-not $files) {
  Write-Host "ℹ️ No .html files found under $templatesPath" -ForegroundColor Yellow
  exit 0
}

# Regex patterns:
# 1) <a ...>Delete</a>   -> add onclick confirm (if not present)
$rxAnchorDelete = '<a(?<attrs>[^>]*?)>(?<text>\s*Delete\s*)<\/a>'
# 2) <button ...>Delete</button> -> add onclick confirm (if not present)
$rxButtonDelete = '<button(?<attrs>[^>]*?)>(?<text>\s*Delete\s*)<\/button>'
# 3) <form ...>...</form> that contains Delete text inside -> add onsubmit confirm (if not present)
#    This is a simple heuristic: any form with "delete" in its content (case-insensitive).
$rxForm = '<form(?<attrs>[^>]*)>(?<content>.*?)<\/form>'

# Helpers to see if attribute already exists
function Has-OnClick($attrs) {
  return ($attrs -match '\bonclick\s*=')
}
function Has-OnSubmit($attrs) {
  return ($attrs -match '\bonsubmit\s*=')
}

$confirmJs = "return confirm('$ConfirmText')"

$changed = 0
$examined = 0
$timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')

foreach ($f in $files) {
  $examined++
  $orig = Get-Content $f.FullName -Raw
  $content = $orig
  $modifiedHere = $false

  # 1) Patch <a>Delete</a>
  $content = [System.Text.RegularExpressions.Regex]::Replace(
    $content, $rxAnchorDelete,
    {
      param($m)
      $attrs = $m.Groups['attrs'].Value
      $text  = $m.Groups['text'].Value

      # Only patch if the visible text contains the word Delete (case-insensitive)
      if ($text -match '(?i)\bdelete\b') {
        if (-not (Has-OnClick $attrs)) {
          # inject onclick before closing '>'
          $patchedAttrs = $attrs.TrimEnd() + " onclick=`"$confirmJs`""
          $script:modifiedHere = $true
          return "<a$patchedAttrs>$text</a>"
        }
      }
      return $m.Value
    },
    'IgnoreCase, Singleline'
  )

  # 2) Patch <button>Delete</button>
  $content = [System.Text.RegularExpressions.Regex]::Replace(
    $content, $rxButtonDelete,
    {
      param($m)
      $attrs = $m.Groups['attrs'].Value
      $text  = $m.Groups['text'].Value

      if ($text -match '(?i)\bdelete\b') {
        if (-not (Has-OnClick $attrs)) {
          $patchedAttrs = $attrs.TrimEnd() + " onclick=`"$confirmJs`""
          $script:modifiedHere = $true
          return "<button$patchedAttrs>$text</button>"
        }
      }
      return $m.Value
    },
    'IgnoreCase, Singleline'
  )

  # 3) Patch <form> ... (contains "delete") ... </form>
  $content = [System.Text.RegularExpressions.Regex]::Replace(
    $content, $rxForm,
    {
      param($m)
      $attrs   = $m.Groups['attrs'].Value
      $inner   = $m.Groups['content'].Value

      if ($inner -match '(?i)\bdelete\b') {
        if (-not (Has-OnSubmit $attrs)) {
          $patchedAttrs = $attrs.TrimEnd() + " onsubmit=`"$confirmJs`""
          $script:modifiedHere = $true
          return "<form$patchedAttrs>$inner</form>"
        }
      }
      return $m.Value
    },
    'IgnoreCase, Singleline'
  )

  if ($modifiedHere -and $content -ne $orig) {
    $backup = "$($f.FullName).bak.$timestamp"
    Copy-Item $f.FullName $backup
    Set-Content -Path $f.FullName -Value $content -Encoding UTF8
    Write-Host "✅ Patched: $($f.FullName)" -ForegroundColor Green
    Write-Host "   ↳ Backup: $backup" -ForegroundColor Yellow
    $changed++
  } else {
    # Uncomment if you want verbose logging for unchanged files
    # Write-Host "• No change: $($f.FullName)" -ForegroundColor DarkGray
  }
}

Write-Host ""
Write-Host "Examined: $examined file(s)" -ForegroundColor Cyan
Write-Host "Changed : $changed file(s)" -ForegroundColor Cyan

if ($changed -eq 0) {
  Write-Host "ℹ️ Nothing matched. Your templates may already be protected, or 'Delete' uses different wording." -ForegroundColor Yellow
  Write-Host "   Tip: Search your templates for buttons/links/forms that trigger deletion and ensure they include a confirm()."
}
