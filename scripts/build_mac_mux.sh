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
    pyinstaller) echo "Run PyInstaller → OnTheSpot.app" ;;
    package_dmg) echo "Package into .dmg" ;;
    cleanup) echo "Clean up build artifacts" ;;
    *) echo "$1" ;;
  esac
}

# ── Helpers ───────────────────────────────────────────────────
step_done()   { [ -f "$STATE_DIR/$1.done" ]; }
mark_done()   { touch "$STATE_DIR/$1.done"; }
mark_failed() { touch "$STATE_DIR/$1.failed"; }
clear_step()  { rm -f "$STATE_DIR/$1.done" "$STATE_DIR/$1.failed"; }

step_status() {
  local step="$1"
  if [ -f "$STATE_DIR/$step.done" ]; then   echo "done"
  elif [ -f "$STATE_DIR/$step.failed" ]; then echo "failed"
  else                                         echo "pending"
  fi
}

# ── Dashboard ─────────────────────────────────────────────────
print_dashboard() {
  local active="${1:-}"
  clear
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║     OnTheSpot  ·  macOS Build Multiplexer    ║${RESET}"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${RESET}"
  echo ""
  local i=1
  for step in "${STEPS[@]}"; do
    local status
    status=$(step_status "$step")
    local label="$(get_step_label "$step")"
    local icon color
    if [ "$step" = "$active" ]; then
      icon="⟳" ; color="${YELLOW}"
    elif [ "$status" = "done" ]; then
      icon="✔" ; color="${GREEN}"
    elif [ "$status" = "failed" ]; then
      icon="✘" ; color="${RED}"
    else
      icon="○" ; color="${DIM}${WHITE}"
    fi
    printf "  ${color}${BOLD}%s${RESET}  ${color}%-3s %s${RESET}\n" "$icon" "$i." "$label"
    if [ "$step" = "$active" ]; then
      echo -e "       ${DIM}└─ log: .build_logs/${step}.log${RESET}"
    fi
    (( i++ ))
  done
  echo ""
}

# ── Step implementations ──────────────────────────────────────

run_env_setup() {
  local log="$LOG_DIR/env_setup.log"
  rm -f "$ROOT/dist/OnTheSpot.tar.gz"
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

  local FFBIN=""
  if [ -f "$ROOT/dist/ffmpeg" ]; then
    FFBIN="--add-binary=$ROOT/dist/ffmpeg:onthespot/bin/ffmpeg"
  else
    echo "WARNING: dist/ffmpeg not found — bundling without ffmpeg." >> "$log"
  fi

  pyinstaller --windowed \
    --hidden-import="zeroconf._utils.ipaddress" \
    --hidden-import="zeroconf._handlers.answers" \
    --add-data="$ROOT/src/onthespot/qt/qtui/*.ui:onthespot/qt/qtui" \
    --add-data="$ROOT/src/onthespot/resources/icons/*.png:onthespot/resources/icons" \
    --add-data="$ROOT/src/onthespot/resources/translations/*.qm:onthespot/resources/translations" \
    $FFBIN \
    --paths="$ROOT/src/onthespot" \
    --name="OnTheSpot" \
    --icon="$ROOT/src/onthespot/resources/icons/onthespot.png" \
    "$ROOT/src/portable.py" \
    --distpath "$ROOT/dist" \
    --workpath "$ROOT/build" \
    --specpath "$ROOT" \
    >> "$log" 2>&1
}

run_package_dmg() {
  local log="$LOG_DIR/package_dmg.log"
  if [ ! -d "$ROOT/dist/OnTheSpot.app" ]; then
    echo "ERROR: OnTheSpot.app not found! PyInstaller must have failed silently." >> "$log"
    return 1
  fi
  chmod +x "$ROOT/dist/OnTheSpot.app" >> "$log" 2>&1
  mkdir -p "$ROOT/dist/dmg"
  # Clean up any previous dmg staging
  rm -rf "$ROOT/dist/dmg/OnTheSpot.app" "$ROOT/dist/dmg/Applications"
  mv "$ROOT/dist/OnTheSpot.app" "$ROOT/dist/dmg/OnTheSpot.app" || return 1
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

  rm -f "$ROOT/dist/OnTheSpot.dmg"
  hdiutil create -srcfolder "$ROOT/dist/dmg" \
    -format UDZO -o "$ROOT/dist/OnTheSpot.dmg" >> "$log" 2>&1
}

run_cleanup() {
  local log="$LOG_DIR/cleanup.log"
  rm -rf "$ROOT/__pycache__" "$ROOT/build" "$ROOT/builder" "$ROOT/venv" "$ROOT"/*.spec \
    >> "$log" 2>&1
}

# ── Dispatcher ────────────────────────────────────────────────
run_step() {
  local step="$1"
  print_dashboard "$step"
  echo -e "  ${CYAN}Running: $(get_step_label "$step")${RESET}"
  echo -e "  ${DIM}Tail log: tail -f .build_logs/${step}.log${RESET}\n"

  rm -f "$STATE_DIR/$step.failed"
  : > "$LOG_DIR/${step}.log"   # truncate log

  set +e
  "run_$step"
  local status=$?
  set -e

  if [ $status -eq 0 ]; then
    mark_done "$step"
    echo -e "  ${GREEN}✔ Done: $(get_step_label "$step")${RESET}\n"
    sleep 0.5
  else
    mark_failed "$step"
    print_dashboard
    echo -e "\n  ${RED}✘ FAILED: $(get_step_label "$step")${RESET}"
    echo -e "  ${DIM}Last 5 lines of .build_logs/${step}.log:${RESET}"
    tail -n 5 "$LOG_DIR/${step}.log" | sed 's/^/    /'
    echo -e "\n  ${DIM}See full log: .build_logs/${step}.log${RESET}"
    exit 1
  fi
}

# ── Main ──────────────────────────────────────────────────────
cd "$ROOT"

case "${1:-}" in
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
    echo "  --reset             Clear all step state (start fresh)"
    echo "  --reset-from STEP   Re-run from STEP onwards"
    echo "  --step STEP         Force-run a single step"
    echo "  --status            Show step status and exit"
    echo ""
    echo "Steps: ${STEPS[*]}"
    exit 0
    ;;
esac

# Default: run all pending steps
echo -e "\n${BOLD}Starting OnTheSpot macOS build...${RESET}\n"
for step in "${STEPS[@]}"; do
  if step_done "$step"; then
    echo -e "  ${GREEN}✔ Skipping (already done):${RESET} $(get_step_label "$step")"
  else
    run_step "$step"
  fi
done

print_dashboard
echo -e "${BOLD}${GREEN}Build complete! → dist/OnTheSpot.dmg${RESET}\n"
