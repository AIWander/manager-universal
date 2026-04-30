# Manager MCP Server — Doctor Script
# Checks binary, backend availability, and task state directory

$ErrorActionPreference = "Continue"
$pass = 0
$fail = 0

function Test-Check {
    param([string]$Name, [bool]$Result, [string]$Detail)
    if ($Result) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "         $Detail" -ForegroundColor Yellow }
        $script:fail++
    }
}

Write-Host ""
Write-Host "Manager MCP Server — Doctor" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host ""

# --- Binary check ---
Write-Host "Binary" -ForegroundColor White
$binaryPaths = @(
    "C:\CPC\servers\manager.exe",
    "C:\CPC\servers\arm64\manager.exe"
)
$foundBinary = $false
foreach ($p in $binaryPaths) {
    if (Test-Path $p) {
        $info = Get-Item $p
        $size = [math]::Round($info.Length / 1KB)
        Test-Check "Binary found" $true "$p (${size} KB, modified $($info.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
        $foundBinary = $true
        break
    }
}
if (-not $foundBinary) {
    Test-Check "Binary found" $false "Not found at: $($binaryPaths -join ', ')"
}

Write-Host ""

# --- Backend checks ---
Write-Host "Backends (at least one required)" -ForegroundColor White
$backendsFound = 0

# Claude Code
$claudeAvail = $null -ne (Get-Command "claude" -ErrorAction SilentlyContinue)
Test-Check "Claude Code CLI (claude)" $claudeAvail $(if ($claudeAvail) { "Available" } else { "Not found in PATH" })
if ($claudeAvail) { $backendsFound++ }

# Codex
$codexAvail = $null -ne (Get-Command "codex" -ErrorAction SilentlyContinue)
Test-Check "Codex CLI (codex)" $codexAvail $(if ($codexAvail) { "Available" } else { "Not found in PATH" })
if ($codexAvail) { $backendsFound++ }

# Gemini
$geminiAvail = ($null -ne (Get-Command "gemini" -ErrorAction SilentlyContinue)) -or ($null -ne $env:GEMINI_API_KEY)
$geminiDetail = if ($null -ne (Get-Command "gemini" -ErrorAction SilentlyContinue)) { "CLI available" } elseif ($null -ne $env:GEMINI_API_KEY) { "GEMINI_API_KEY set" } else { "No CLI and no GEMINI_API_KEY" }
Test-Check "Gemini (CLI or API key)" $geminiAvail $geminiDetail
if ($geminiAvail) { $backendsFound++ }

# GPT
$gptAvail = $null -ne $env:OPENAI_API_KEY
Test-Check "GPT (OPENAI_API_KEY)" $gptAvail $(if ($gptAvail) { "OPENAI_API_KEY set" } else { "OPENAI_API_KEY not set" })
if ($gptAvail) { $backendsFound++ }

Write-Host ""
if ($backendsFound -eq 0) {
    Write-Host "  [WARN] No backends available. Manager needs at least one." -ForegroundColor Yellow
    $fail++
} else {
    Write-Host "  $backendsFound backend(s) available." -ForegroundColor Green
}

Write-Host ""

# --- Task state directory ---
Write-Host "Task State" -ForegroundColor White
$stateDir = "$env:APPDATA\cpc\manager\tasks"
if (Test-Path $stateDir) {
    $writable = $true
    try {
        $testFile = Join-Path $stateDir ".doctor_test"
        Set-Content -Path $testFile -Value "test" -ErrorAction Stop
        Remove-Item $testFile -ErrorAction SilentlyContinue
    } catch {
        $writable = $false
    }
    Test-Check "Task state directory" $writable "$stateDir (exists, $(if ($writable) {'writable'} else {'NOT writable'}))"
} else {
    # Try to create it
    try {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        Test-Check "Task state directory" $true "$stateDir (created)"
    } catch {
        Test-Check "Task state directory" $false "Cannot create $stateDir"
    }
}

Write-Host ""
Write-Host "===========================" -ForegroundColor Cyan
Write-Host "  $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Yellow" })
Write-Host ""

exit $fail
