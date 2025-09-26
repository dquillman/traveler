param(
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Labels
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$env:DJANGO_SETTINGS_MODULE = 'config.settings_test'

if (-not $Labels -or $Labels.Count -eq 0) {
  $Labels = @('stays')
}

python manage.py test -v 2 @Labels

