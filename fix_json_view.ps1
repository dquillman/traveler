# fix_json_view.ps1 — clean up JsonResponse syntax issues and add stays_map_data
$ErrorActionPreference = "Stop"
$file = "stays\views.py"
if (-not (Test-Path $file)) { Write-Error "Missing stays\views.py"; exit 1 }

# 1) Backup
$ts  = (Get-Date).ToString("yyyyMMdd_HHmmss")
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

# 2) Load file (lines and raw)
$lines = Get-Content -Encoding UTF8 $file
$text  = [string]::Join("`r`n", $lines)

# 3) Ensure 'from django.http import JsonResponse'
if ($text -notmatch '(?m)^\s*from\s+django\.http\s+import\s+JsonResponse(\s*,|\s*$)') {
    # find a good place among imports (after the last 'from django...' or 'import' block)
    $insertIndex = 0
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*(from|import)\s+') { $insertIndex = $i }
        else {
            # stop once imports end (blank line or first non-import)
            if ($lines[$i].Trim() -eq "") { $insertIndex = $i }
            break
        }
    }
    $before = if ($insertIndex -lt $lines.Count) { $lines[0..$insertIndex] } else { $lines }
    $after  = if ($insertIndex -lt ($lines.Count-1)) { $lines[($insertIndex+1)..($lines.Count-1)] } else { @() }
    $lines  = @() + $before + @('from django.http import JsonResponse') + $after
    Write-Host "Inserted: from django.http import JsonResponse"
}

# 4) Comment out any top-level stray 'return JsonResponse(...)' lines
# (top-level means it starts at column 0 or only spaces, not inside a def/class)
$changedReturn = $false
for ($i=0; $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    if ($ln -match '^[ \t]*return\s+JsonResponse\s*\(') {
        # Heuristic: If previous non-empty, non-comment line doesn't look like we're in a function, comment it out
        $j = $i - 1
        $inDef = $false
        while ($j -ge 0) {
            $prev = $lines[$j].Trim()
            if ($prev -eq "") { $j--; continue }
            if ($prev -match '^(def|class)\s+') { $inDef = $true }
            break
        }
        if (-not $inDef) {
            $lines[$i] = "# FIXED by script: top-level return removed`r`n# " + $ln
            $changedReturn = $true
        }
    }
}
if ($changedReturn) { Write-Host "Commented out stray top-level 'return JsonResponse(...)' line(s)." }

# 5) Replace or append a clean stays_map_data(request) view
$block_map = @'
def stays_map_data(request):
    qs = Stay.objects.exclude(latitude__isnull=True).exclude(longitude__isnull=True)
    stays = list(qs.values("id", "city", "state", "latitude", "longitude"))
    return JsonResponse({"stays": stays})
'@

# Function replace helper (regex matches from def line to next def/class or EOF)
function Replace-PyDef {
    param([string]$Source, [string]$FuncName, [string]$Replacement)
    $pattern = "(?ms)^[ \t]*def[ \t]+$([regex]::Escape($FuncName))[ \t]*\([^\)]*\)[ \t]*:[\s\S]*?(?=^[ \t]*(def|class)[ \t]+\w+[ \t]*\(|\Z)"
    if ([regex]::IsMatch($Source, $pattern)) {
        return ([regex]::Replace($Source, $pattern, $Replacement))
    } else {
        return $null
    }
}

# Join current lines to text for regex ops
$text = [string]::Join("`r`n", $lines)

$updated = Replace-PyDef -Source $text -FuncName "stays_map_data" -Replacement $block_map
if ($null -ne $updated) {
    $text = $updated
    Write-Host "Replaced: stays_map_data"
} else {
    $text = $text.TrimEnd() + "`r`n`r`n" + $block_map + "`r`n"
    Write-Host "Appended: stays_map_data"
}

# 6) Write back
Set-Content -Path $file -Value $text -Encoding UTF8
Write-Host "Wrote updated: $file"

Write-Host "Next: python -m py_compile stays\views.py"
