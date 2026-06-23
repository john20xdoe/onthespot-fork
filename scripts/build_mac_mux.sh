#!/bin/bash
# =============================================================
#  OnTheSpot macOS Build Multiplexer
#  Breaks the build into discrete, resumable steps.
#  State is tracked via .build_state/<step>.done marker files.
#  Usage:
#    ./scripts/build_mac_mux.sh           # run all pending steps
#    ./scripts/build_mac_mux.sh --reset   # clear state & restart
#    ./scripts/build_mac_mux.sh --status  # show step status only
# =============================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="$ROOT/.build_state"
LOG_DIR="$ROOT/.build_logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"

# Hide cursor and restore on exit
printf "\033[?25l"
restore_cursor() {
  printf "\033[?25h"
}
trap restore_cursor EXIT

# ── ANSI colours ─────────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BLUE='\033[0;34m'
WHITE='\033[0;37m'

# ── Steps definition (ordered) ───────────────────────────────
STEPS=(
  "env_setup"
  "pip_install"
  "ffmpeg"
  "pyinstaller"
  "package_dmg"
  "cleanup"
)

get_step_label() {
  case "$1" in
    env_setup) echo "Prepare environment & venv" ;;
    pip_install) echo "Install Python dependencies" ;;
    ffmpeg) echo "Build / acquire ffmpeg binary" ;;
    pyinstaller) echo "Run PyInstaller → OnTheSpotRebuilt.app" ;;
    package_dmg) echo "Package into .dmg" ;;
    cleanup) echo "Clean up build artifacts" ;;
    *) echo "$1" ;;
  esac
}

# ── Helpers ───────────────────────────────────────────────────
step_status() {
  local step="$1"
  if [ "${DMG_MODE:-0}" -eq 1 ] && { [ "$step" = "env_setup" ] || [ "$step" = "pip_install" ] || [ "$step" = "ffmpeg" ]; }; then
    echo "done"
  elif [ -f "$STATE_DIR/$step.done" ]; then   echo "done"
  elif [ -f "$STATE_DIR/$step.failed" ]; then echo "failed"
  else                                         echo "pending"
  fi
}

step_done()   { [ "$(step_status "$1")" = "done" ]; }
mark_done()   { touch "$STATE_DIR/$1.done"; }
mark_failed() { touch "$STATE_DIR/$1.failed"; }
clear_step()  { rm -f "$STATE_DIR/$1.done" "$STATE_DIR/$1.failed"; }

# ── Dashboard ─────────────────────────────────────────────────
print_dashboard() {
  local active="${1:-}"
  local spinner_frame="${2:-⟳}"
  
  # Go to home position instead of full clear to prevent flicker
  printf "\033[H"
  
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════╗${RESET}\033[K"
  echo -e "${BOLD}${BLUE}║     OnTheSpot  ·  macOS Build Multiplexer    ║${RESET}\033[K"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${RESET}\033[K"

  local total_steps=${#STEPS[@]}
  local completed_steps=0
  for s in "${STEPS[@]}"; do
    if [ "$(step_status "$s")" = "done" ]; then
      ((completed_steps++))
    fi
  done

  local percent=$(( completed_steps * 100 / total_steps ))
  local bar_length=32
  local filled_len=$(( completed_steps * bar_length / total_steps ))
  local empty_len=$(( bar_length - filled_len ))

  local bar_filled=""
  for ((j=0; j<filled_len; j++)); do bar_filled="${bar_filled}█"; done

  local bar_empty=""
  for ((j=0; j<empty_len; j++)); do bar_empty="${bar_empty}░"; done

  echo -e "  Progress: [${GREEN}${bar_filled}${RESET}${DIM}${bar_empty}${RESET}] ${percent}%\033[K"
  echo -e "\033[K"

  local i=1
  for s in "${STEPS[@]}"; do
    local status
    status=$(step_status "$s")
    local label="$(get_step_label "$s")"
    local icon color
    if [ "$s" = "$active" ]; then
      icon="$spinner_frame" ; color="${CYAN}"
    elif [ "$status" = "done" ]; then
      icon="✔" ; color="${GREEN}"
    elif [ "$status" = "failed" ]; then
      icon="✘" ; color="${RED}"
    else
      icon="○" ; color="${DIM}${WHITE}"
    fi
    printf "  ${color}${BOLD}%s${RESET}  ${color}%-3s %s${RESET}\033[K\n" "$icon" "$i." "$label"
    if [ "$s" = "$active" ]; then
      echo -e "       ${DIM}└─ log: .build_logs/${s}.log${RESET}\033[K"
      local clean_line=""
      if [ -f "$LOG_DIR/${s}.log" ]; then
        local last_line
        last_line=$(tail -n 1 "$LOG_DIR/${s}.log" 2>/dev/null | tr -d '\r\n' | cut -c1-65)
        if [ -n "$last_line" ]; then
          clean_line=$(echo "$last_line" | sed 's/\x1b\[[0-9;]*m//g')
        fi
      fi
      if [ -n "$clean_line" ]; then
        printf "          ${CYAN}▶  %s${RESET}\033[K\n" "$clean_line"
      else
        printf "          ${DIM}▶  waiting...${RESET}\033[K\n"
      fi
    fi
    (( i++ ))
  done
  echo -e "\033[K"
  # Clear any remaining lines below the dashboard
  printf "\033[J"
}

# ── Step implementations ──────────────────────────────────────

run_env_setup() {
  local log="$LOG_DIR/env_setup.log"
  rm -f "$ROOT/dist/OnTheSpotRebuilt.tar.gz"
  mkdir -p "$ROOT/build" "$ROOT/dist" "$ROOT/builder"
  python3 -m venv "$ROOT/venv" >> "$log" 2>&1
}

run_pip_install() {
  local log="$LOG_DIR/pip_install.log"
  "$ROOT/venv/bin/pip" install --upgrade pip wheel pyinstaller >> "$log" 2>&1
  "$ROOT/venv/bin/pip" install -r "$ROOT/requirements.txt" >> "$log" 2>&1
}

run_ffmpeg() {
  local log="$LOG_DIR/ffmpeg.log"
  if [ -f "$ROOT/dist/ffmpeg" ]; then
    echo "ffmpeg binary already present, skipping build." >> "$log"
    return 0
  fi

  mkdir -p "$ROOT/build" "$ROOT/dist" "$ROOT/builder"

  # Attempt to use local/brew ffmpeg first if not forced to build
  local use_brew=1
  if [ "${DMG_MODE:-0}" -ne 1 ] && [ "${BUILD_FFMPEG:-0}" -eq 1 ]; then
    use_brew=0
  fi

  if [ "$use_brew" -eq 1 ]; then
    local brew_ffmpeg=""
    if command -v ffmpeg >/dev/null 2>&1; then
      brew_ffmpeg="$(command -v ffmpeg)"
    elif [ -f "/opt/homebrew/bin/ffmpeg" ]; then
      brew_ffmpeg="/opt/homebrew/bin/ffmpeg"
    elif [ -f "/usr/local/bin/ffmpeg" ]; then
      brew_ffmpeg="/usr/local/bin/ffmpeg"
    fi

    if [ -n "$brew_ffmpeg" ]; then
      echo "Found local/brew ffmpeg at $brew_ffmpeg, copying to dist/ffmpeg..." >> "$log"
      # cp without options dereferences symlinks, copying the actual binary file
      cp "$brew_ffmpeg" "$ROOT/dist/ffmpeg" >> "$log" 2>&1
      chmod +x "$ROOT/dist/ffmpeg"
      return 0
    fi
  else
    echo "Forcing ffmpeg compile/download because --build-ffmpeg is active." >> "$log"
  fi

  if uname -m | grep -q x86_64; then
    # Intel: download pre-built binary
    curl -L -o "$ROOT/build/ffmpeg.zip" \
      https://evermeet.cx/ffmpeg/ffmpeg-7.1.zip >> "$log" 2>&1
    unzip "$ROOT/build/ffmpeg.zip" -d "$ROOT/dist" >> "$log" 2>&1
  else
    # Apple Silicon: compile from source
    curl -L -o "$ROOT/build/ffmpeg.zip" \
      https://github.com/markus-perl/ffmpeg-build-script/archive/refs/heads/master.zip \
      >> "$log" 2>&1
    unzip "$ROOT/build/ffmpeg.zip" -d "$ROOT/builder" >> "$log" 2>&1
    cd "$ROOT/builder/ffmpeg-build-script-master"
    ./build-ffmpeg --build --skip-install >> "$log" 2>&1
    cp workspace/bin/ffmpeg "$ROOT/dist/ffmpeg" || true
    cd "$ROOT"
  fi
  if [ ! -f "$ROOT/dist/ffmpeg" ]; then
    echo "ERROR: ffmpeg was not built successfully!" >> "$log"
    return 1
  fi
  chmod +x "$ROOT/dist/ffmpeg"
}

run_pyinstaller() {
  local log="$LOG_DIR/pyinstaller.log"
  source "$ROOT/venv/bin/activate"

  mkdir -p "$ROOT/build" "$ROOT/dist"

  local FFBIN=""
  if [ -f "$ROOT/dist/ffmpeg" ]; then
    FFBIN="--add-binary=$ROOT/dist/ffmpeg:onthespot/bin/ffmpeg"
  else
    echo "WARNING: dist/ffmpeg not found — bundling without ffmpeg." >> "$log"
  fi

  pyinstaller --windowed --noconfirm \
    --hidden-import="zeroconf._utils.ipaddress" \
    --hidden-import="zeroconf._handlers.answers" \
    --add-data="$ROOT/src/onthespot/qt/qtui/*.ui:onthespot/qt/qtui" \
    --add-data="$ROOT/src/onthespot/resources/icons/*.png:onthespot/resources/icons" \
    --add-data="$ROOT/src/onthespot/resources/translations/*.qm:onthespot/resources/translations" \
    --add-data="$ROOT/src/onthespot/resources/theme.qss:onthespot/resources" \
    $FFBIN \
    --paths="$ROOT/src/onthespot" \
    --name="OnTheSpotRebuilt" \
    --icon="$ROOT/src/onthespot/resources/icons/onthespot.png" \
    "$ROOT/src/portable.py" \
    --distpath "$ROOT/dist" \
    --workpath "$ROOT/build" \
    --specpath "$ROOT" \
    >> "$log" 2>&1
}

run_package_dmg() {
  local log="$LOG_DIR/package_dmg.log"
  if [ ! -d "$ROOT/dist/OnTheSpotRebuilt.app" ]; then
    echo "ERROR: OnTheSpotRebuilt.app not found! PyInstaller must have failed silently." >> "$log"
    return 1
  fi
  chmod +x "$ROOT/dist/OnTheSpotRebuilt.app" >> "$log" 2>&1
  mkdir -p "$ROOT/dist/dmg"
  # Clean up any previous dmg staging
  chmod -R +w "$ROOT/dist/dmg/OnTheSpotRebuilt.app" 2>/dev/null || true
  chflags -R nouchg "$ROOT/dist/dmg/OnTheSpotRebuilt.app" 2>/dev/null || true
  
  local trash_app="$ROOT/dist/dmg/OnTheSpotRebuilt.app.trash.$$."
  if mv "$ROOT/dist/dmg/OnTheSpotRebuilt.app" "$trash_app" 2>/dev/null; then
    rm -rf "$trash_app" 2>/dev/null || true
  else
    rm -rf "$ROOT/dist/dmg/OnTheSpotRebuilt.app" 2>/dev/null || true
  fi
  rm -rf "$ROOT/dist/dmg/Applications"
  mv "$ROOT/dist/OnTheSpotRebuilt.app" "$ROOT/dist/dmg/OnTheSpotRebuilt.app" || return 1
  ln -s /Applications "$ROOT/dist/dmg/Applications"

  cat > "$ROOT/dist/dmg/readme.txt" <<'EOF'
# Login Issues
Newer versions of macOS have restricted networking features
for apps inside the 'Applications' folder. To login to your
account you will need to:

1. Run the following command in terminal:
   echo "127.0.0.1 $HOST" | sudo tee -a /etc/hosts

2. Launch the app and click add account before dragging into
   the Applications folder.

3. After successfully logging in you can drag the app into
   the folder.

# Security Issues
If you experience an error while trying to launch the app,
open the 'Applications' folder, right-click the app, and
click "Open Anyway".
EOF

  rm -f "$ROOT/dist/OnTheSpotRebuilt.dmg"
  hdiutil create -srcfolder "$ROOT/dist/dmg" \
    -format UDZO -o "$ROOT/dist/OnTheSpotRebuilt.dmg" >> "$log" 2>&1
}

run_cleanup() {
  local log="$LOG_DIR/cleanup.log"
  rm -rf "$ROOT/__pycache__" "$ROOT/build" "$ROOT/builder" "$ROOT"/*.spec \
    >> "$log" 2>&1
}

# ── Dispatcher ────────────────────────────────────────────────
run_step() {
  local step="$1"
  print_dashboard "$step"
  echo -e "  ${CYAN}Running: $(get_step_label "$step")${RESET}\033[K"
  echo -e "  ${DIM}Tail log: tail -f .build_logs/${step}.log${RESET}\033[K"
  echo -e "\033[K"

  rm -f "$STATE_DIR/$step.failed"
  : > "$LOG_DIR/${step}.log"   # truncate log

  # Spin characters (highly visible rotating quadrant blocks)
  local spin_chars=("▘" "▝" "▗" "▖")
  local spin_count=${#spin_chars[@]}
  local idx=0

  set +e
  # Run step function in a background subshell enforcing set -e, redirecting all outputs to the log
  ( set -e; "run_$step" ) >> "$LOG_DIR/${step}.log" 2>&1 &
  local pid=$!
  
  # Trap Ctrl-C to kill the background process if interrupted
  trap 'kill $pid 2>/dev/null; exit 1' INT TERM
  
  while kill -0 $pid 2>/dev/null; do
    local frame="${spin_chars[$idx]}"
    idx=$(( (idx + 1) % spin_count ))
    print_dashboard "$step" "$frame"
    echo -e "  ${CYAN}Running: $(get_step_label "$step")${RESET}\033[K"
    echo -e "  ${DIM}Tail log: tail -f .build_logs/${step}.log${RESET}\033[K"
    echo -e "\033[K"
    sleep 0.1
  done
  
  # Reset trap
  trap - INT TERM
  wait $pid
  local status=$?
  set -e

  if [ $status -eq 0 ]; then
    mark_done "$step"
    print_dashboard
    echo -e "  ${GREEN}✔ Done: $(get_step_label "$step")${RESET}\033[K"
    echo -e "\033[K"
    sleep 0.5
  else
    mark_failed "$step"
    print_dashboard
    echo -e "\033[K\n  ${RED}✘ FAILED: $(get_step_label "$step")${RESET}\033[K"
    echo -e "  ${DIM}Last 5 lines of .build_logs/${step}.log:${RESET}\033[K"
    tail -n 5 "$LOG_DIR/${step}.log" | sed 's/^/    /' | sed 's/$/\x1b[K/'
    echo -e "\033[K\n  ${DIM}See full log: .build_logs/${step}.log${RESET}\033[K"
    exit 1
  fi
}

# ── Main ──────────────────────────────────────────────────────
cd "$ROOT"

DMG_MODE=0
BUILD_FFMPEG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dmg)
      DMG_MODE=1
      shift
      ;;
    --build-ffmpeg)
      BUILD_FFMPEG=1
      shift
      ;;
    --reset)
      echo -e "${YELLOW}Resetting build state...${RESET}"
      rm -rf "$STATE_DIR"
      mkdir -p "$STATE_DIR"
      echo -e "${GREEN}Done. All steps marked as pending.${RESET}"
      exit 0
      ;;
    --reset-from)
      step="${2:-}"
      if [ -z "$step" ]; then
        echo "Usage: $0 --reset-from <step_name>"
        echo "Steps: ${STEPS[*]}"
        exit 1
      fi
      found=0
      for s in "${STEPS[@]}"; do
        if [ "$found" = "1" ] || [ "$s" = "$step" ]; then
          clear_step "$s"
          found=1
        fi
      done
      echo -e "${GREEN}Reset from step '$step' onwards.${RESET}"
      exit 0
      ;;
    --status)
      print_dashboard
      exit 0
      ;;
    --step)
      # Run a single named step, ignoring done state
      step="${2:-}"
      clear_step "$step"
      run_step "$step"
      print_dashboard
      exit 0
      ;;
    --help|-h)
      echo "Usage: $0 [option]"
      echo ""
      echo "Options:"
      echo "  (none)              Run all pending steps"
      echo "  --dmg               DMG build mode (skip to step 4, verify steps 1-3)"
      echo "  --build-ffmpeg      Force compile/download ffmpeg instead of copying from brew (full/normal mode only)"
      echo "  --reset             Clear all step state (start fresh)"
      echo "  --reset-from STEP   Re-run from STEP onwards"
      echo "  --step STEP         Force-run a single step"
      echo "  --status            Show step status and exit"
      echo ""
      echo "Steps: ${STEPS[*]}"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

verify_dmg_mode_requirements() {
  echo -e "\n${BOLD}${CYAN}Verifying DMG build mode prerequisites (Steps 1-3)...${RESET}"
  local failed=0

  # Step 1: Prepare environment & venv
  if [ ! -d "$ROOT/venv" ] || [ ! -f "$ROOT/venv/bin/activate" ]; then
    echo -e "  ${RED}✘ Step 1 Verification Failed: Virtual environment (venv) is missing at $ROOT/venv.${RESET}"
    failed=1
  else
    echo -e "  ${GREEN}✔ Step 1 Verification Passed: Virtual environment exists.${RESET}"
  fi

  # Step 2: Install Python dependencies (specifically pyinstaller)
  if [ ! -f "$ROOT/venv/bin/pyinstaller" ]; then
    echo -e "  ${RED}✘ Step 2 Verification Failed: PyInstaller is missing in virtual environment at $ROOT/venv/bin/pyinstaller.${RESET}"
    failed=1
  else
    echo -e "  ${GREEN}✔ Step 2 Verification Passed: PyInstaller dependency exists.${RESET}"
  fi

  # Step 3: Build / acquire ffmpeg binary
  if [ ! -f "$ROOT/dist/ffmpeg" ]; then
    echo -e "  ${RED}✘ Step 3 Verification Failed: ffmpeg binary is missing at $ROOT/dist/ffmpeg.${RESET}"
    failed=1
  else
    echo -e "  ${GREEN}✔ Step 3 Verification Passed: ffmpeg binary exists.${RESET}"
  fi

  if [ $failed -eq 1 ]; then
    echo -e "\n${YELLOW}Prerequisites for DMG build mode are missing.${RESET}"
    echo -e "Please run the script without the ${BOLD}--dmg${RESET} flag first to initialize the environment and download dependencies:"
    echo -e "  ${CYAN}./scripts/build_mac_mux.sh${RESET}\n"
    exit 1
  fi
  echo -e "${GREEN}Verification successful! Skipping steps 1-3.${RESET}\n"
}

check_overwrite_dist() {
  local has_rebuildable=0
  if [ -d "$ROOT/dist" ]; then
    for name in "OnTheSpotRebuilt.app" "OnTheSpotRebuilt" "OnTheSpotRebuilt.dmg" "dmg"; do
      if [ -e "$ROOT/dist/$name" ]; then
        has_rebuildable=1
        break
      fi
    done
  fi

  if [ "$has_rebuildable" -eq 1 ]; then
    # Make sure cursor is visible for prompt
    printf "\033[?25h"
    echo -e "${YELLOW}Warning: Build output directory 'dist/' contains existing build outputs that will be replaced.${RESET}"
    read -p "Overwrite and replace the built DMG/app? (y/n): " confirm
    # Re-hide cursor
    printf "\033[?25l"
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}Cleaning existing build outputs from dist/...${RESET}"
      for name in "OnTheSpotRebuilt.app" "OnTheSpotRebuilt" "OnTheSpotRebuilt.dmg" "dmg"; do
        local item="$ROOT/dist/$name"
        if [ -e "$item" ]; then
          chmod -R +w "$item" 2>/dev/null || true
          chflags -R nouchg "$item" 2>/dev/null || true
          
          # Workaround for macOS Finder locking .DS_Store: rename before deleting
          local trash_dir="${item}.trash.$$."
          if mv "$item" "$trash_dir" 2>/dev/null; then
            rm -rf "$trash_dir" 2>/dev/null || true
          else
            rm -rf "$item" 2>/dev/null || true
          fi
        fi
      done
      # Reset entire build state to ensure clean build from scratch
      echo -e "${YELLOW}Resetting build state...${RESET}"
      rm -rf "$STATE_DIR"
      mkdir -p "$STATE_DIR"
    else
      echo -e "${RED}Build aborted by user.${RESET}"
      exit 1
    fi
  fi
}

if [ "$DMG_MODE" -eq 1 ]; then
  # Reset build state to ensure steps 4-6 are always executed and not skipped
  rm -rf "$STATE_DIR"
  mkdir -p "$STATE_DIR"
  verify_dmg_mode_requirements
fi

# Default: run all pending steps
check_overwrite_dist

# Clear screen once at start of build if output is a TTY
if [ -t 1 ]; then
  clear
fi

echo -e "\n${BOLD}Starting OnTheSpot macOS build...${RESET}\n"
for step in "${STEPS[@]}"; do
  if step_done "$step"; then
    echo -e "  ${GREEN}✔ Skipping (already done):${RESET} $(get_step_label "$step")"
  else
    run_step "$step"
  fi
done

print_dashboard
echo -e "${BOLD}${GREEN}Build complete! → dist/OnTheSpotRebuilt.dmg${RESET}\n"
