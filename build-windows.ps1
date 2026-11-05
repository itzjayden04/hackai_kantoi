# Builds Kantoi-android.apk on a Windows PC, the same way GitHub Actions does.
#
# Run from the project folder (the one with README.md):
#   powershell -ExecutionPolicy Bypass -File .\build-windows.ps1
#
# Options:
#   -SkipTests   skip flutter analyze and flutter test (faster, not recommended)
#   -Install     install the APK on a phone connected by USB (needs adb)
#
# Keys: copy app\secrets.example.json to app\secrets.json and fill in the keys
# you have. Without it the app still builds and runs on its built-in checks.
# See docs\build-on-windows.md.

param(
    [switch]$SkipTests,
    [switch]$Install
)

# 'Continue', not 'Stop': Windows PowerShell 5.1 can treat Flutter's normal
# progress output on stderr as an error. Failures are caught by exit code.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$app = Join-Path $root 'app'

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "`nBuild stopped: $text" -ForegroundColor Red; exit 1 }
function Run($exe, [string[]]$argList) {
    & $exe @argList
    if ($LASTEXITCODE -ne 0) { Fail "'$exe $($argList -join ' ')' failed (exit code $LASTEXITCODE)." }
}

if (-not (Test-Path (Join-Path $app 'pubspec.yaml'))) { Fail "run this script from the Kantoi project folder (app\pubspec.yaml not found)." }

Step 'Checking Flutter'
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) { Fail "Flutter is not installed or not on PATH. See docs\build-on-windows.md, step 1." }
$versionJson = (& flutter --version --machine | Out-String)
$found = $null
if ($versionJson -match '"frameworkVersion"\s*:\s*"([0-9.]+)"') { $found = [version]$Matches[1] }
if ($found) {
    Write-Host "Flutter $found"
    if ($found -lt [version]'3.47.0') { Fail "Kantoi needs Flutter 3.47 or later (CI uses 3.47.7). Run 'flutter upgrade'." }
} else {
    Write-Host 'Could not read the Flutter version; continuing.' -ForegroundColor Yellow
}

Push-Location $app
try {
    Step 'Getting packages (flutter pub get)'
    Run 'flutter' @('pub', 'get')

    if (-not $SkipTests) {
        Step 'Checking the code (flutter analyze)'
        Run 'flutter' @('analyze')
        Step 'Running the tests (flutter test)'
        Run 'flutter' @('test')
    }

    $buildArgs = @('build', 'apk', '--release', '--obfuscate', '--split-debug-info=build/symbols')
    $secrets = Join-Path $app 'secrets.json'
    if (Test-Path $secrets) {
        Write-Host "`nUsing keys from app\secrets.json"
        $buildArgs += '--dart-define-from-file=secrets.json'
    } else {
        Write-Host "`nNo app\secrets.json: building without keys (built-in checks only)." -ForegroundColor Yellow
    }
    if (-not (Test-Path (Join-Path $app 'android\key.properties'))) {
        Write-Host 'No android\key.properties: the APK is signed with the debug key.' -ForegroundColor Yellow
        Write-Host 'A phone with the GitHub release installed must uninstall it before installing this build.' -ForegroundColor Yellow
    }

    Step 'Building the APK (flutter build apk)'
    Run 'flutter' $buildArgs

    $apk = Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $apk)) { Fail "the build finished but $apk is missing." }
    $out = Join-Path $root 'Kantoi-android.apk'
    Copy-Item $apk $out -Force -ErrorAction Stop
    $mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Write-Host "`nDone: $out ($mb MB)" -ForegroundColor Green

    if ($Install) {
        Step 'Installing on the connected phone (adb install)'
        if (-not (Get-Command adb -ErrorAction SilentlyContinue)) { Fail "adb not found. Add Android SDK platform-tools to PATH, or copy the APK to the phone yourself." }
        Run 'adb' @('install', '-r', $out)
        Write-Host 'Installed. Open Kantoi on the phone and follow setup.' -ForegroundColor Green
    }
}
finally {
    Pop-Location
}
