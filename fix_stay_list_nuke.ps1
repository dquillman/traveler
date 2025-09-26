# fix_stay_list_nuke.ps1
$ErrorActionPreference = 'Stop'
$file = 'stays\views.py'
if (-not (Test-Path $file)) { Write-Error 'Missing stays\views.py'; exit 1 }

# Backup
$ts  = (Get-Date).ToString('yyyyMMdd_HHmmss')
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

# Read text
$text  = Get-Content -Raw -Encoding UTF8 $file

# Clean stay_list block
$replacement_stay_list = @'
def stay_list(request):
    qs = Stay.objects.all()

    state_choices = list(
        Stay.objects.values_list("state", flat=True)
        .exclude(state__isnull=True)
        .exclude(state__exact="")
        .distinct()
        .order_by("state")
    )

    city_choices = list(
        Stay.objects.values_list("city", flat=True)
        .exclude(city__isnull=True)
        .exclude(city__exact="")
        .distinct()
        .order_by("city")
    )

    rating_choices = [1, 2, 3, 4, 5]

    qs = _apply_stay_filters(qs, request)

    context = {
        "stays": qs,
        "state_choices": state_choices,
        "city_choices": city_choices,
        "rating_choices": rating_choices,
    }
    return render(request, "stays/stay_list.html", context)
'@

# Regex: from def stay_list(...) to next top-level def/class or EOF
$patStayList = '(?ms)^[ \t]*def[ \t]+stay_list[ \t]*\([^\)]*\)[ \t]*:[\s\S]*?(?=^[ \t]*(def|class)[ \t]+\w+[ \t]*\(|\Z)'
if ([regex]::IsMatch($text, $patStayList)) {
    $text = [regex]::Replace($text, $patStayList, $replacement_stay_list, 1)
    Write-Host 'Replaced: stay_list (first occurrence)'
} else {
    # If missing entirely, just append a clean one
    $text = $text.TrimEnd() + "`r`n`r`n" + $replacement_stay_list + "`r`n"
    Write-Host 'Appended: stay_list (was missing)'
}

# Extra safety: comment lone braces/brackets in lines 30–60
$lines = $text -split "`r?`n"
for ($i=29; $i -le 59 -and $i -lt $lines.Count; $i++) {
    $trim = $lines[$i].Trim()
    if ($trim -eq '{' -or $trim -eq '}' -or $trim -eq '[') {
        $lines[$i] = '# FIXED stray brace: ' + $lines[$i]
        Write-Host ("Commented stray brace on line {0}" -f ($i+1))
    }
}
$text = [string]::Join("`r`n", $lines)

# Write back
Set-Content -Path $file -Value $text -Encoding UTF8
Write-Host 'Wrote updated: stays\views.py'

# Compile check
try {
    & python -m py_compile $file
    Write-Host 'Python compile OK.'
} catch {
    Write-Warning 'Python reported an error. Paste the file/line/caret so I can zero in.'
}
