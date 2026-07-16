# =============================================================
#  OnTheSpot Windows Build Multiplexer
#  Breaks the build into discrete, resumable steps.
#  State is tracked via build/state/<step>.done marker files.
#  Usage:
#    powershell .\scripts\build_mux_windows.ps1
#    powershell .\scripts\build_mux_windows.ps1 -Reset
#    powershell .\scripts\build_mux_windows.ps1 -Status
# =============================================================

param (
    [switch]$Status,
    [switch]$Reset,
    [string]$ResetFrom,
    [string]$Step,
    [switch]$BuildFFmpeg
)

$ErrorActionPreference = "Stop"

# Setup root and directory layouts
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ROOT = Resolve-Path "$SCRIPT_DIR\.."
$STATE_DIR = "$ROOT\build\state\windows"
$LOG_DIR = "$ROOT\build\logs\windows"

if (-not (Test-Path $STATE_DIR)) { New-Item -ItemType Directory -Path $STATE_DIR -Force | Out-Null }
if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

$STEPS = @(
    "env_setup",
    "pip_install",
    "ffmpeg",
    "pyinstaller",
    "cleanup"
)

function Get-StepLabel($step) {
    switch ($step) {
        "env_setup"   { "Prepare environment & venv" }
        "pip_install" { "Install Python dependencies" }
        "ffmpeg"      { "Acquire ffmpeg binary" }
        "pyinstaller" { "Run PyInstaller -> OnTheSpot.exe" }
        "cleanup"     { "Clean up build artifacts" }
        default       { $step }
    }
}

function Get-StepStatus($step) {
    if (Test-Path "$STATE_DIR\$step.done") { "done" }
    elseif (Test-Path "$STATE_DIR\$step.failed") { "failed" }
    else { "pending" }
}

function Mark-Done($step) {
    New-Item -Path "$STATE_DIR\$step.done" -ItemType File -Force | Out-Null
}

function Mark-Failed($step) {
    New-Item -Path "$STATE_DIR\$step.failed" -ItemType File -Force | Out-Null
}

function Clear-Step($step) {
    Remove-Item -Path "$STATE_DIR\$step.done" -ErrorAction SilentlyContinue
    Remove-Item -Path "$STATE_DIR\$step.failed" -ErrorAction SilentlyContinue
    Remove-Item -Path "$STATE_DIR\$step.time" -ErrorAction SilentlyContinue
}

function Get-StepDuration($step) {
    if (Test-Path "$STATE_DIR\$step.time") {
        Get-Content "$STATE_DIR\$step.time" | Out-String | ForEach-Object { $_.Trim() }
    }
}

# ── Dashboard ─────────────────────────────────────────────────
function Show-Dashboard($activeStep, $spinnerFrame, $elapsed) {
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║     OnTheSpot · Windows Build Multiplexer    ║" -ForegroundColor Blue
    Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Blue

    $total = $STEPS.Length
    $doneCount = 0
    foreach ($s in $STEPS) {
        if ((Get-StepStatus $s) -eq "done") { $doneCount++ }
    }
    $percent = [math]::Floor(($doneCount / $total) * 100)
    $barLength = 32
    $filledLen = [math]::Floor(($doneCount / $total) * $barLength)
    $emptyLen = $barLength - $filledLen
    $bar = ("█" * $filledLen) + ("░" * $emptyLen)

    Write-Host "  Progress: [$bar] $percent%" -ForegroundColor Green
    Write-Host ""

    $i = 1
    foreach ($s in $STEPS) {
        $status = Get-StepStatus $s
        $label = Get-StepLabel $s
        $icon = "○"
        $color = "DarkGray"
        
        if ($s -eq $activeStep) {
            $icon = $spinnerFrame
            $color = "Cyan"
        } elseif ($status -eq "done") {
            $icon = "✔"
            $color = "Green"
        } elseif ($status -eq "failed") {
            $icon = "✘"
            $color = "Red"
        }

        $durStr = ""
        if ($s -eq $activeStep -and $elapsed -ne $null) {
            $durStr = " (${elapsed}s)"
        } else {
            $dur = Get-StepDuration $s
            if ($dur) { $durStr = " (${dur}s)" }
        }

        Write-Host "  $icon  $i. $label$durStr" -ForegroundColor $color
        if ($s -eq $activeStep) {
            Write-Host "       └─ log: build\logs\$s.log" -ForegroundColor DarkGray
            $logFile = "$LOG_DIR\$s.log"
            if (Test-Path $logFile) {
                $lastLine = Get-Content $logFile -Tail 1 -ErrorAction SilentlyContinue
                if ($lastLine) {
                    Write-Host "          ▶  $lastLine" -ForegroundColor Cyan
                } else {
                    Write-Host "          ▶  waiting..." -ForegroundColor DarkGray
                }
            } else {
                Write-Host "          ▶  waiting..." -ForegroundColor DarkGray
            }
        }
        $i++
    }
    Write-Host ""
}

# ── Main Arguments Handling ────────────────────────────────────

if ($Reset) {
    Write-Host "Resetting build state..." -ForegroundColor Yellow
    foreach ($s in $STEPS) {
        Clear-Step $s
    }
    Write-Host "Done. All steps marked as pending." -ForegroundColor Green
    exit 0
}

if ($ResetFrom) {
    $found = $false
    foreach ($s in $STEPS) {
        if ($found -or $s -eq $ResetFrom) {
            Clear-Step $s
            $found = $true
        }
    }
    Write-Host "Reset from step '$ResetFrom' onwards." -ForegroundColor Green
    exit 0
}

if ($Status) {
    Show-Dashboard
    exit 0
}

# ── Step implementations ──────────────────────────────────────

function Run-Step($stepName) {
    $startTime = Get-Date
    $logFile = "$LOG_DIR\$stepName.log"
    
    Remove-Item -Path "$STATE_DIR\$stepName.failed" -ErrorAction SilentlyContinue
    Remove-Item -Path "$STATE_DIR\$stepName.time" -ErrorAction SilentlyContinue
    New-Item -Path $logFile -ItemType File -Force | Out-Null
    
    Show-Dashboard $stepName "▘" 0
    
    $forceFFmpeg = $BuildFFmpeg
    $job = Start-Job -ScriptBlock {
        param($step, $rootDir, $logPath, $forceFfmpegFlag)
        $ErrorActionPreference = "Stop"
        
        $ROOT = $rootDir
        
        switch ($step) {
            "env_setup" {
                New-Item -ItemType Directory -Path "$ROOT\build\dist" -Force | Out-Null
                New-Item -ItemType Directory -Path "$ROOT\build\deps" -Force | Out-Null
                
                # Check for python executable and run venv
                $process = Start-Process -FilePath "python" -ArgumentList "-m venv `"$ROOT\venvwin`"" -NoNewWindow -PassThru -Wait -RedirectStandardOutput $logPath -RedirectStandardError $logPath
                if ($process.ExitCode -ne 0) {
                    throw "python -m venv failed with exit code $($process.ExitCode)"
                }
            }
            "pip_install" {
                $pythonPath = "$ROOT\venvwin\Scripts\python.exe"
                $pipPath = "$ROOT\venvwin\Scripts\pip.exe"
                
                $process1 = Start-Process -FilePath $pythonPath -ArgumentList "-m pip install --upgrade pip wheel pyinstaller" -NoNewWindow -PassThru -Wait -RedirectStandardOutput $logPath -RedirectStandardError $logPath
                if ($process1.ExitCode -ne 0) {
                    throw "pip upgrade failed with exit code $($process1.ExitCode)"
                }
                
                $process2 = Start-Process -FilePath $pipPath -ArgumentList "install -r `"$ROOT\requirements.txt`"" -NoNewWindow -PassThru -Wait -RedirectStandardOutput $logPath -RedirectStandardError $logPath
                if ($process2.ExitCode -ne 0) {
                    throw "pip requirements install failed with exit code $($process2.ExitCode)"
                }
            }
            "ffmpeg" {
                $zipPath = "$ROOT\build\deps\ffmpeg.zip"
                
                if ($forceFfmpegFlag -or -not (Test-Path $zipPath)) {
                    Add-Content -Path $logPath -Value "Downloading FFmpeg release..."
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Invoke-WebRequest -Uri "https://github.com/GyanD/codexffmpeg/releases/download/7.1/ffmpeg-7.1-essentials_build.zip" -OutFile $zipPath
                }
                
                if ($forceFfmpegFlag -or -not (Test-Path "$ROOT\build\deps\ffmpeg")) {
                    Add-Content -Path $logPath -Value "Unpacking FFmpeg..."
                    Remove-Item -Path "$ROOT\build\deps\ffmpeg" -Recurse -Force -ErrorAction SilentlyContinue
                    Expand-Archive -Path $zipPath -DestinationPath "$ROOT\build\deps\ffmpeg" -Force
                }
                Add-Content -Path $logPath -Value "FFmpeg setup complete."
            }
            "pyinstaller" {
                $pyinstallerPath = "$ROOT\venvwin\Scripts\pyinstaller.exe"
                
                # Check for ffmpeg binary
                $ffmpegExe = "$ROOT\build\deps\ffmpeg\ffmpeg-7.1-essentials_build\bin\ffmpeg.exe"
                if (-not (Test-Path $ffmpegExe)) {
                    $found = Get-ChildItem -Path "$ROOT\build\deps\ffmpeg" -Filter "ffmpeg.exe" -Recurse | Select-Object -First 1
                    if ($found) {
                        $ffmpegExe = $found.FullName
                    }
                }
                
                $ffmpegArg = ""
                if (Test-Path $ffmpegExe) {
                    $ffmpegArg = "--add-binary=`"$ffmpegExe;onthespot/bin/ffmpeg`""
                } else {
                    Add-Content -Path $logPath -Value "WARNING: ffmpeg.exe not found! Bundling without FFmpeg."
                }
                
                $argsList = @(
                    "--onefile",
                    "--noconsole",
                    "--noconfirm",
                    "--hidden-import=zeroconf._utils.ipaddress",
                    "--hidden-import=zeroconf._handlers.answers",
                    "--add-data=`"$ROOT\src\onthespot\resources\translations\*.qm;onthespot/resources/translations`"",
                    "--add-data=`"$ROOT\src\onthespot\qt\qtui\*.ui;onthespot/qt/qtui`"",
                    "--add-data=`"$ROOT\src\onthespot\resources\icons\*.png;onthespot/resources/icons`"",
                    "--add-data=`"$ROOT\src\onthespot\resources\theme.qss;onthespot/resources`"",
                    $ffmpegArg,
                    "--paths=`"$ROOT\src\onthespot`"",
                    "--name=OnTheSpot",
                    "--icon=`"$ROOT\src\onthespot\resources\icons\onthespot.png`"",
                    "--distpath=`"$ROOT\build\dist`"",
                    "--workpath=`"$ROOT\build\pyinstaller_work`"",
                    "--specpath=`"$ROOT\build`"",
                    "`"$ROOT\src\portable.py`""
                )
                
                $argsList = $argsList | Where-Object { $_ -ne "" }
                $process = Start-Process -FilePath $pyinstallerPath -ArgumentList $argsList -NoNewWindow -PassThru -Wait -RedirectStandardOutput $logPath -RedirectStandardError $logPath
                if ($process.ExitCode -ne 0) {
                    throw "PyInstaller execution failed with exit code $($process.ExitCode)"
                }
            }
            "cleanup" {
                Remove-Item -Path "$ROOT\build\*.spec" -ErrorAction SilentlyContinue
                Remove-Item -Path "$ROOT\build\pyinstaller_work" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } -ArgumentList $stepName, $ROOT, $logFile, $forceFFmpeg
    
    $spinChars = @("▘", "▝", "▗", "▖")
    $idx = 0
    
    while ($job.State -eq "Running") {
        $elapsed = [math]::Floor(((Get-Date) - $startTime).TotalSeconds)
        Show-Dashboard $stepName $spinChars[$idx] $elapsed
        $idx = ($idx + 1) % $spinChars.Length
        Start-Sleep -Milliseconds 200
    }
    
    $jobState = $job.State
    Remove-Job -Job $job
    
    $duration = [math]::Floor(((Get-Date) - $startTime).TotalSeconds)
    
    if ($jobState -eq "Completed") {
        $hasError = $false
        if ($stepName -eq "pyinstaller" -and -not (Test-Path "$ROOT\build\dist\OnTheSpot.exe")) {
            $hasError = $true
        }
        
        if (-not $hasError) {
            $duration | Out-File -FilePath "$STATE_DIR\$stepName.time" -Force
            Mark-Done $stepName
            Show-Dashboard $null
            Write-Host "  ✔ Done: $(Get-StepLabel $stepName) (${duration}s)" -ForegroundColor Green
            Write-Host ""
            Start-Sleep -Milliseconds 500
        } else {
            Mark-Failed $stepName
            Show-Dashboard $null
            Write-Host "  ✘ FAILED: $(Get-StepLabel $stepName) (${duration}s)" -ForegroundColor Red
            if (Test-Path $logFile) {
                Write-Host "  Last 5 lines of build\logs\$stepName.log:" -ForegroundColor DarkGray
                Get-Content $logFile -Tail 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            }
            Write-Host "  See full log: build\logs\$stepName.log" -ForegroundColor DarkGray
            exit 1
        }
    } else {
        Mark-Failed $stepName
        Show-Dashboard $null
        Write-Host "  ✘ FAILED (Job execution failed): $(Get-StepLabel $stepName) (${duration}s)" -ForegroundColor Red
        Write-Host "  See log: build\logs\$stepName.log" -ForegroundColor DarkGray
        exit 1
    }
}

if ($Step) {
    Clear-Step $Step
    Run-Step $Step
    Show-Dashboard
    exit 0
}

# Overwrite check function
function Check-OverwriteDist {
    $hasRebuildable = $false
    if (Test-Path "$ROOT\build\dist\OnTheSpot.exe") {
        $hasRebuildable = $true
    }

    if ($hasRebuildable) {
        Write-Host "Warning: Build output directory 'build\dist\' contains existing build outputs that will be replaced." -ForegroundColor Yellow
        $confirm = Read-Host "Overwrite and replace the built executable? (y/n)"
        if ($confirm -match "^[Yy]$") {
            Write-Host "Cleaning existing build outputs from build\dist\..." -ForegroundColor Yellow
            Remove-Item -Path "$ROOT\build\dist\OnTheSpot.exe" -ErrorAction SilentlyContinue
            foreach ($s in $STEPS) {
                Clear-Step $s
            }
        } else {
            Write-Host "Build aborted by user." -ForegroundColor Red
            exit 1
        }
    }
}

Check-OverwriteDist

Write-Host "`nStarting OnTheSpot Windows build...`n" -ForegroundColor White
foreach ($s in $STEPS) {
    if ((Get-StepStatus $s) -eq "done") {
        Write-Host "  ✔ Skipping (already done): $(Get-StepLabel $s)" -ForegroundColor Green
    } else {
        Run-Step $s
    }
}

Show-Dashboard
Write-Host "Build complete! Executable available as 'build\dist\OnTheSpot.exe'`n" -ForegroundColor Green
