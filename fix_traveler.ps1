# fix_traveler.ps1
# Fixes syntax errors in stays\views.py and removes unused vars flagged by Ruff.
# Creates timestamped backups before modifying files.

$ErrorActionPreference = "Stop"

function Backup-File($Path) {
    if (Test-Path $Path) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        Copy-Item $Path "$Path.bak.$stamp"
    }
}

function Fix-Unused-Variables {
    Write-Host ">> Cleaning unused variables (Ruff F841)..." -ForegroundColor Cyan

    $patchFile = "patch_detail_edit_fix.py"
    if (Test-Path $patchFile) {
        Backup-File $patchFile
        $txt = Get-Content -Raw $patchFile

        # Remove line: changed = False  (only when it looks like a top-level or indented variable assign)
        $txt2 = $txt -replace '^\s*changed\s*=\s*False\s*\r?\n', '', 'Multiline'

        if ($txt2 -ne $txt) {
            Set-Content -Path $patchFile -Value $txt2 -NoNewline
            Write-Host "   - Removed 'changed = False' in $patchFile"
        } else {
            Write-Host "   - Nothing to change in $patchFile"
        }
    }

    $verifyFile = "verify_stays_setup.py"
    if (Test-Path $verifyFile) {
        Backup-File $verifyFile
        $txt = Get-Content -Raw $verifyFile

        # Replace 'urls = import_module(' with 'import_module(' (keeps the call, drops unused assignment)
        $txt2 = $txt -replace '^\s*urls\s*=\s*import_module\(', 'import_module(', 'Multiline'

        if ($txt2 -ne $txt) {
            Set-Content -Path $verifyFile -Value $txt2 -NoNewline
            Write-Host "   - Removed unused 'urls =' assignment in $verifyFile"
        } else {
            Write-Host "   - Nothing to change in $verifyFile"
        }
    }
}

function Fix-ViewsPy {
    $views = "stays\views.py"
    if (-not (Test-Path $views)) {
        Write-Host "!! $views not found. Skipping." -ForegroundColor Yellow
        return
    }

    Write-Host ">> Patching $views ..." -ForegroundColor Cyan
    Backup-File $views

    $lines = Get-Content $views
    $count = $lines.Count
    if ($count -eq 0) { Write-Host "   - File empty? Skipping." ; return }

    # Find the 'nights = int(row.get("nights")' line that starts the bad block
    $nightsIdx = $null
    for ($i = 0; $i -lt $count; $i++) {
        if ($lines[$i] -match 'nights\s*=\s*int\(\s*row\.get\("nights"\)') {
            $nightsIdx = $i
            break
        }
    }
    if ($null -eq $nightsIdx) {
        Write-Host "   - Could not find the 'nights = int(row.get(\"nights\") ...' line. Skipping repair." -ForegroundColor Yellow
        return
    }

    # Walk backward to find the 'try:' that should precede it in the same block
    $startTryIdx = $null
    for ($j = $nightsIdx; $j -ge 0; $j--) {
        if ($lines[$j] -match '^\s*try:\s*$') {
            $startTryIdx = $j
            break
        }
        # stop if we hit a def or return or blank line run-away (prevents overshoot)
        if ($lines[$j] -match '^\s*def\s+\w+\(') { break }
    }
    if ($null -eq $startTryIdx) {
        Write-Host "   - Could not locate the 'try:' that wraps the nights parse. Skipping repair." -ForegroundColor Yellow
        return
    }

    # Find the end of the broken region: we’ll go through the success message + redirect
    # Start searching after nightsIdx, look for 'messages.success(' then the next 'return'
    $msgIdx = $null
    for ($k = $nightsIdx; $k -lt $count; $k++) {
        if ($lines[$k] -match 'messages\.success\(') { $msgIdx = $k; break }
    }
    if ($null -eq $msgIdx) {
        Write-Host "   - Could not find messages.success(..) after the parse block. Skipping repair." -ForegroundColor Yellow
        return
    }

    $returnIdx = $null
    for ($m = $msgIdx; $m -lt $count; $m++) {
        if ($lines[$m] -match '^\s*return\b') { $returnIdx = $m; break }
    }
    if ($null -eq $returnIdx) {
        # If no explicit return found after messages, set to msgIdx so we at least replace through the message
        $returnIdx = $msgIdx
    }

    # Determine base indent from the 'try:' line so we can keep style consistent
    $indentMatch = [regex]::Match($lines[$startTryIdx], '^(?<indent>\s*)try:\s*$')
    $baseIndent = $indentMatch.Groups['indent'].Value
    $i1 = $baseIndent + ' ' * 4
    $i2 = $baseIndent + ' ' * 8

    # Build the corrected block with dynamic indentation
    $fixedBlock = @()
    $fixedBlock += "$baseIndent# Parse numeric fields safely"
    $fixedBlock += "$baseIndent" + "try:"
    $fixedBlock += "$i1" + "nights = int(row.get(""nights"") or 0)"
    $fixedBlock += "$baseIndent" + "except (TypeError, ValueError):"
    $fixedBlock += "$i1" + "nights = 0"
    $fixedBlock += ""
    $fixedBlock += "$baseIndent" + "try:"
    $fixedBlock += "$i1" + 'rate = float(row.get("rate/nt") or row.get("rate_per_night") or 0)'
    $fixedBlock += "$baseIndent" + "except (TypeError, ValueError):"
    $fixedBlock += "$i1" + "rate = 0.0"
    $fixedBlock += ""
    $fixedBlock += "$baseIndent" + "try:"
    $fixedBlock += "$i1" + 'price = float('
    $fixedBlock += "$i2" + 'row.get("price/night")'
    $fixedBlock += "$i2" + 'or row.get("price_per_night")'
    $fixedBlock += "$i2" + 'or row.get("price")'
    $fixedBlock += "$i2" + 'or 0'
    $fixedBlock += "$i1" + ')'
    $fixedBlock += "$baseIndent" + "except (TypeError, ValueError):"
    $fixedBlock += "$i1" + "price = 0.0"
    $fixedBlock += ""
    $fixedBlock += "$baseIndent" + 'paid = (row.get("paid?") or row.get("paid") or "").strip().lower() in {'
    $fixedBlock += "$i1" + '"yes",'
    $fixedBlock += "$i1" + '"true",'
    $fixedBlock += "$i1" + '"1",'
    $fixedBlock += "$i1" + '"y",'
    $fixedBlock += "$i1" + '"paid",'
    $fixedBlock += "$baseIndent" + "}"
    $fixedBlock += ""
    $fixedBlock += "$baseIndent" + "# Write/update the Stay"
    $fixedBlock += "$baseIndent" + "obj, is_created = Stay.objects.update_or_create("
    $fixedBlock += "$i1" + "park=park,"
    $fixedBlock += "$i1" + "city=city,"
    $fixedBlock += "$i1" + "state=state,"
    $fixedBlock += "$i1" + "check_in=check_in,"
    $fixedBlock += "$i1" + "defaults={"
    $fixedBlock += "$i2" + '"nights": nights,'
    $fixedBlock += "$i2" + '"rate_per_night": rate,'
    $fixedBlock += "$i2" + '"price_per_night": price,'
    $fixedBlock += "$i2" + '"paid": paid,'
    $fixedBlock += "$i2" + '"site": row.get("site") or "",'
    $fixedBlock += "$i2" + '"check_out": check_out,'
    $fixedBlock += "$i1" + "},"
    $fixedBlock += "$baseIndent" + ")"
    $fixedBlock += "$baseIndent" + "created += int(is_created)"
    $fixedBlock += "$baseIndent" + "updated += int(not is_created)"
    $fixedBlock += ""
    $fixedBlock += "$baseIndent" + "messages.success("
    $fixedBlock += "$i1" + "request,"
    $fixedBlock += "$i1" + 'f"Import complete. Created {created}, updated {updated}, skipped {skipped}.",'
    $fixedBlock += "$baseIndent" + ")"
    $fixedBlock += "$baseIndent" + 'return redirect("stay_list")'

    # Replace the broken region with the fixed block
    $pre  = if ($startTryIdx -gt 0) { $lines[0..($startTryIdx-1)] } else { @() }
    $post = if ($returnIdx -lt ($count-1)) { $lines[($returnIdx+1)..($count-1)] } else { @() }

    $newLines = @()
    $newLines += $pre
    $newLines += $fixedBlock
    $newLines += $post

    Set-Content -Path $views -Value ($newLines -join "`r`n") -NoNewline
    Write-Host "   - Rewrote malformed try/except block and closing return in $views" -ForegroundColor Green
}

try {
    Push-Location (Get-Location)

    Fix-Unused-Variables
    Fix-ViewsPy

    Write-Host ">> Running Ruff + Black..." -ForegroundColor Cyan
    try {
        ruff --version | Out-Null
        ruff check . --fix
    } catch {
        Write-Host "   - Ruff not found or failed. Install with: python -m pip install ruff" -ForegroundColor Yellow
    }

    try {
        black --version | Out-Null
        black .
    } catch {
        Write-Host "   - Black not found or failed. Install with: python -m pip install black" -ForegroundColor Yellow
    }

    Write-Host "`nAll done. If any errors persist, re-run Ruff to see the exact lines." -ForegroundColor Cyan
}
finally {
    Pop-Location
}
