#!/bin/bash
# =============================================================
#  OnTheSpot Linux Build Multiplexer
#  Breaks the build into discrete, resumable steps.
#  State is tracked via build/state/<step>.done marker files.
#  Usage:
#    ./scripts/build_mux_linux.sh           # run all pending steps
#    ./scripts/build_mux_linux.sh --reset   # clear state & restart
#    ./scripts/build_mux_linux.sh --status  # show step status only
# =============================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="$ROOT/build/state/linux"
LOG_DIR="$ROOT/build/logs/linux"
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
  "build_wheel"
  "pyinstaller"
  "appimage"
  "rpm"
  "cleanup"
)

get_step_label() {
  case "$1" in
    env_setup) echo "Prepare environment & venv" ;;
    pip_install) echo "Install Python dependencies" ;;
    ffmpeg) echo "Acquire ffmpeg binary" ;;
    build_wheel) echo "Compile OnTheSpot python wheel" ;;
    pyinstaller) echo "Run PyInstaller → tarball" ;;
    appimage) echo "Build AppImage package" ;;
    rpm) echo "Build RPM package" ;;
    cleanup) echo "Clean up build artifacts" ;;
    *) echo "$1" ;;
  esac
}

# ── Targets management ─────────────────────────────────────────
TARGET_TARBALL=0
TARGET_APPIMAGE=0
TARGET_RPM=0
BUILD_FFMPEG=0

is_step_active() {
  local step="$1"
  case "$step" in
    env_setup|pip_install|cleanup)
      return 0
      ;;
    ffmpeg)
      if [ "$TARGET_TARBALL" -eq 1 ] || [ "$TARGET_APPIMAGE" -eq 1 ]; then
        return 0
      else
        return 1
      fi
      ;;
    build_wheel)
      if [ "$TARGET_APPIMAGE" -eq 1 ] || [ "$TARGET_RPM" -eq 1 ]; then
        return 0
      else
        return 1
      fi
      ;;
    pyinstaller)
      if [ "$TARGET_TARBALL" -eq 1 ]; then
        return 0
      else
        return 1
      fi
      ;;
    appimage)
      if [ "$TARGET_APPIMAGE" -eq 1 ]; then
        return 0
      else
        return 1
      fi
      ;;
    rpm)
      if [ "$TARGET_RPM" -eq 1 ]; then
        return 0
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

step_status() {
  local step="$1"
  if ! is_step_active "$step"; then
    STATUS_VAL="na"
  elif [ -f "$STATE_DIR/$step.done" ]; then
    STATUS_VAL="done"
  elif [ -f "$STATE_DIR/$step.failed" ]; then
    STATUS_VAL="failed"
  else
    STATUS_VAL="pending"
  fi
}

step_done() {
  step_status "$1"
  [ "$STATUS_VAL" = "done" ] || [ "$STATUS_VAL" = "na" ]
}

mark_done()   { touch "$STATE_DIR/$1.done"; }
mark_failed() { touch "$STATE_DIR/$1.failed"; }
clear_step()  { rm -f "$STATE_DIR/$1.done" "$STATE_DIR/$1.failed" "$STATE_DIR/$1.time"; }

get_step_duration() {
  local step="$1"
  DURATION_VAL=""
  if [ -f "$STATE_DIR/$step.time" ]; then
    DURATION_VAL=$(cat "$STATE_DIR/$step.time")
  fi
}

# ── Dashboard ─────────────────────────────────────────────────
print_dashboard() {
  local active="${1:-}"
  local spinner_frame="${2:-⟳}"
  local elapsed="${3:-}"
  
  # Go to home position instead of full clear to prevent flicker
  printf "\033[H"
  
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════╗${RESET}\033[K"
  echo -e "${BOLD}${BLUE}║      OnTheSpot  ·  Linux Build Multiplexer   ║${RESET}\033[K"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${RESET}\033[K"

  local total_active=0
  local completed_active=0
  for s in "${STEPS[@]}"; do
    if is_step_active "$s"; then
      total_active=$(( total_active + 1 ))
      step_status "$s"
      if [ "$STATUS_VAL" = "done" ]; then
        completed_active=$(( completed_active + 1 ))
      fi
    fi
  done

  local percent=0
  if [ "$total_active" -gt 0 ]; then
    percent=$(( completed_active * 100 / total_active ))
  fi
  local bar_length=32
  local filled_len=0
  if [ "$total_active" -gt 0 ]; then
    filled_len=$(( completed_active * bar_length / total_active ))
  fi
  local empty_len=$(( bar_length - filled_len ))

  local bar_filled=""
  for ((j=0; j<filled_len; j++)); do bar_filled="${bar_filled}█"; done

  local bar_empty=""
  for ((j=0; j<empty_len; j++)); do bar_empty="${bar_empty}░"; done

  echo -e "  Progress: [${GREEN}${bar_filled}${RESET}${DIM}${bar_empty}${RESET}] ${percent}%\033[K"
  echo -e "\033[K"

  local i=1
  for s in "${STEPS[@]}"; do
    step_status "$s"
    local status="$STATUS_VAL"
    local label="$(get_step_label "$s")"
    local icon color
    if [ "$status" = "na" ]; then
      icon="—" ; color="${DIM}${WHITE}"
      label="${label} (N/A)"
    elif [ "$s" = "$active" ]; then
      icon="$spinner_frame" ; color="${CYAN}"
    elif [ "$status" = "done" ]; then
      icon="✔" ; color="${GREEN}"
    elif [ "$status" = "failed" ]; then
      icon="✘" ; color="${RED}"
    else
      icon="○" ; color="${DIM}${WHITE}"
    fi

    # Read duration
    local duration_str=""
    if [ "$s" = "$active" ] && [ -n "$elapsed" ]; then
      duration_str=" (${elapsed}s)"
    elif [ "$status" = "done" ]; then
      get_step_duration "$s"
      local dur="$DURATION_VAL"
      if [ -n "$dur" ]; then
        duration_str=" (${dur}s)"
      fi
    fi

    printf "  ${color}${BOLD}%s${RESET}  ${color}%-3s %s%s${RESET}\033[K\n" "$icon" "$i." "$label" "$duration_str"
    if [ "$s" = "$active" ]; then
      echo -e "       ${DIM}└─ log: build/logs/linux/${s}.log${RESET}\033[K"
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
    i=$(( i + 1 ))
  done
  echo -e "\033[K"
  # Clear any remaining lines below the dashboard
  printf "\033[J"
}

# ── Step implementations ──────────────────────────────────────

run_env_setup() {
  local log="$LOG_DIR/env_setup.log"
  rm -f "$ROOT/build/dist/OnTheSpot.tar.gz"
  mkdir -p "$ROOT/build/dist" "$ROOT/build/deps" "$ROOT/build/state" "$ROOT/build/logs"
  python3 -m venv "$ROOT/venvlinux" >> "$log" 2>&1
}

run_pip_install() {
  local log="$LOG_DIR/pip_install.log"
  "$ROOT/venvlinux/bin/pip" install --upgrade pip wheel pyinstaller build >> "$log" 2>&1
  "$ROOT/venvlinux/bin/pip" install -r "$ROOT/requirements.txt" >> "$log" 2>&1
}

run_ffmpeg() {
  local log="$LOG_DIR/ffmpeg.log"
  if [ -f "$ROOT/build/deps/ffmpeg" ]; then
    echo "ffmpeg binary already present, skipping acquisition." >> "$log"
    return 0
  fi

  mkdir -p "$ROOT/build/deps"

  # Check if a system-wide ffmpeg exists and we are not forced to download/build
  if [ "$BUILD_FFMPEG" -eq 0 ] && command -v ffmpeg >/dev/null 2>&1; then
    local sys_ffmpeg
    sys_ffmpeg="$(command -v ffmpeg)"
    echo "Found system ffmpeg at $sys_ffmpeg, copying to build/deps/ffmpeg..." >> "$log"
    cp "$sys_ffmpeg" "$ROOT/build/deps/ffmpeg" >> "$log" 2>&1
    chmod +x "$ROOT/build/deps/ffmpeg"
    return 0
  fi

  echo "Downloading static ffmpeg for Linux x86_64..." >> "$log"
  curl -L -o "$ROOT/build/deps/ffmpeg.tar.xz" \
    https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz >> "$log" 2>&1
  
  echo "Extracting ffmpeg..." >> "$log"
  tar -xf "$ROOT/build/deps/ffmpeg.tar.xz" -C "$ROOT/build/deps" >> "$log" 2>&1
  
  # Locate and copy the ffmpeg binary
  find "$ROOT/build/deps" -type f -name ffmpeg -exec cp {} "$ROOT/build/deps/ffmpeg" \; >> "$log" 2>&1
  chmod +x "$ROOT/build/deps/ffmpeg"
  
  # Clean up extracted directory and archive
  rm -rf "$ROOT/build/deps"/ffmpeg-*-amd64-static "$ROOT/build/deps/ffmpeg.tar.xz" >> "$log" 2>&1

  if [ ! -f "$ROOT/build/deps/ffmpeg" ]; then
    echo "ERROR: ffmpeg binary was not acquired successfully!" >> "$log"
    return 1
  fi
}

run_build_wheel() {
  local log="$LOG_DIR/build_wheel.log"
  # Use build module inside our venv to build the wheel
  "$ROOT/venvlinux/bin/python" -m build --outdir "$ROOT/build/dist" >> "$log" 2>&1
}

run_pyinstaller() {
  local log="$LOG_DIR/pyinstaller.log"
  source "$ROOT/venvlinux/bin/activate"

  mkdir -p "$ROOT/build/dist"

  local FFBIN=""
  if [ -f "$ROOT/build/deps/ffmpeg" ]; then
    FFBIN="--add-binary=$ROOT/build/deps/ffmpeg:onthespot/bin/ffmpeg"
  else
    echo "WARNING: build/deps/ffmpeg not found — bundling without ffmpeg." >> "$log"
  fi

  pyinstaller --onefile \
    --hidden-import="zeroconf._utils.ipaddress" \
    --hidden-import="zeroconf._handlers.answers" \
    --add-data="$ROOT/src/onthespot/qt/qtui/*.ui:onthespot/qt/qtui" \
    --add-data="$ROOT/src/onthespot/resources/icons/*.png:onthespot/resources/icons" \
    --add-data="$ROOT/src/onthespot/resources/translations/*.qm:onthespot/resources/translations" \
    --add-data="$ROOT/src/onthespot/resources/theme.qss:onthespot/resources" \
    $FFBIN \
    --paths="$ROOT/src/onthespot" \
    --name=onthespot-gui \
    --icon="$ROOT/src/onthespot/resources/icons/onthespot.png" \
    --distpath="$ROOT/build/dist" \
    --workpath="$ROOT/build/pyinstaller_work" \
    --specpath="$ROOT/build" \
    "$ROOT/src/portable.py" >> "$log" 2>&1

  if [ ! -f "$ROOT/build/dist/onthespot-gui" ]; then
    echo "ERROR: PyInstaller execution failed to create binary!" >> "$log"
    return 1
  fi

  echo "Packaging executable as OnTheSpot.tar.gz..." >> "$log"
  cd "$ROOT/build/dist"
  tar -czvf OnTheSpot.tar.gz onthespot-gui >> "$log" 2>&1
  cd "$ROOT"
}

run_appimage() {
  local log="$LOG_DIR/appimage.log"
  rm -rf "$ROOT/build/appimage_work" "$ROOT/build/dist/OnTheSpot-x86_64.AppImage" >> "$log" 2>&1
  mkdir -p "$ROOT/build/dist" "$ROOT/build/deps" "$ROOT/build/appimage_work"

  cd "$ROOT/build/deps"
  if [ ! -f "appimagetool-x86_64.AppImage" ]; then
    echo "Downloading appimagetool..." >> "$log"
    curl -L -o appimagetool-x86_64.AppImage https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage >> "$log" 2>&1
    chmod +x appimagetool-x86_64.AppImage
  fi

  if [ ! -f "python.AppImage" ]; then
    echo "Downloading Python AppImage..." >> "$log"
    curl -L -o python.AppImage https://github.com/niess/python-appimage/releases/download/python3.12/python3.12.12-cp312-cp312-manylinux2014_x86_64.AppImage >> "$log" 2>&1
    chmod +x python.AppImage
  fi

  cd "$ROOT/build/appimage_work"
  echo "Extracting Python AppImage..." >> "$log"
  ../deps/python.AppImage --appimage-extract >> "$log" 2>&1
  mv squashfs-root OnTheSpot.AppDir

  cd "$ROOT"
  echo "Preparing python environment inside AppDir..." >> "$log"
  "$ROOT/build/appimage_work/OnTheSpot.AppDir/AppRun" -m pip install -r "$ROOT/requirements.txt" >> "$log" 2>&1
  
  # Find the built wheel
  local wheel_file
  wheel_file=$(find "$ROOT/build/dist" -name "onthespot-*-py3-none-any.whl" | head -n 1)
  if [ -z "$wheel_file" ] || [ ! -f "$wheel_file" ]; then
    echo "ERROR: Wheel file not found! build_wheel step should have created it." >> "$log"
    return 1
  fi
  
  echo "Installing OnTheSpot wheel to AppDir..." >> "$log"
  "$ROOT/build/appimage_work/OnTheSpot.AppDir/AppRun" -m pip install "$wheel_file" >> "$log" 2>&1

  cd "$ROOT/build/appimage_work/OnTheSpot.AppDir"
  rm -f AppRun .DirIcon python.png python*.desktop usr/share/applications/python*.desktop

  cp -t . "$ROOT/src/onthespot/resources/icons/onthespot.png" "$ROOT/src/onthespot/resources/org.onthespot.OnTheSpot.desktop" >> "$log" 2>&1
  cp "$ROOT/src/onthespot/resources/org.onthespot.OnTheSpot.desktop" usr/share/applications/ >> "$log" 2>&1

  # Create AppRun launcher
  echo '#! /bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export PATH=$HERE/usr/bin:$PATH;
export APPIMAGE_COMMAND=$(command -v -- "$ARGV0")
export TCL_LIBRARY="${APPDIR}/usr/share/tcltk/tcl8.6"
export TK_LIBRARY="${APPDIR}/usr/share/tcltk/tk8.6"
export TKPATH="${TK_LIBRARY}"
export SSL_CERT_FILE="${APPDIR}/opt/_internal/certs.pem"
"$HERE/opt/python3.12/bin/python3.12" "-m" "onthespot.gui" "$@"' > AppRun

  chmod -R 0755 ../OnTheSpot.AppDir
  chmod +x AppRun

  # Bundle ffmpeg and ffplay
  if [ -f "$ROOT/build/deps/ffmpeg" ]; then
    cp "$ROOT/build/deps/ffmpeg" ../OnTheSpot.AppDir/usr/bin/ >> "$log" 2>&1
  else
    cp "$(which ffmpeg)" ../OnTheSpot.AppDir/usr/bin/ 2>/dev/null || true
  fi
  cp "$(which ffplay)" ../OnTheSpot.AppDir/usr/bin/ 2>/dev/null || true

  # Copy common system dependencies if present
  cp /usr/lib/x86_64-linux-gnu/libxcb-cursor.so* ../OnTheSpot.AppDir/usr/lib/ 2>/dev/null || true
  cp /usr/lib/x86_64-linux-gnu/libxcb-xinerama.so* ../OnTheSpot.AppDir/usr/lib/ 2>/dev/null || true
  cp /usr/lib/x86_64-linux-gnu/libxcb.so* ../OnTheSpot.AppDir/usr/lib/ 2>/dev/null || true
  cp /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so* ../OnTheSpot.AppDir/usr/lib/ 2>/dev/null || true

  # Package into AppImage
  echo "Building AppImage package..." >> "$log"
  cd ..
  ../deps/appimagetool-x86_64.AppImage --appimage-extract >> "$log" 2>&1
  squashfs-root/AppRun OnTheSpot.AppDir >> "$log" 2>&1

  mv OnTheSpot-x86_64.AppImage "$ROOT/build/dist/OnTheSpot-x86_64.AppImage" >> "$log" 2>&1
  cd "$ROOT"
}

run_rpm() {
  local log="$LOG_DIR/rpm.log"
  if ! command -v rpmbuild >/dev/null 2>&1; then
    echo "ERROR: 'rpmbuild' utility is missing. Please install 'rpm-build' (e.g. sudo dnf install rpm-build)." >> "$log"
    return 1
  fi

  # Find the built wheel
  local wheel_file
  wheel_file=$(find "$ROOT/build/dist" -name "onthespot-*-py3-none-any.whl" | head -n 1)
  if [ -z "$wheel_file" ] || [ ! -f "$wheel_file" ]; then
    echo "ERROR: Wheel file not found! build_wheel step should have created it." >> "$log"
    return 1
  fi

  echo "Setting up rpmbuild directories..." >> "$log"
  mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
  
  cp "$wheel_file" ~/rpmbuild/SOURCES/ >> "$log" 2>&1
  cp "$ROOT/src/onthespot/resources/org.onthespot.OnTheSpot.desktop" ~/rpmbuild/SOURCES/ >> "$log" 2>&1
  cp "$ROOT/src/onthespot/resources/icons/onthespot.png" ~/rpmbuild/SOURCES/ >> "$log" 2>&1
  cp "$ROOT/distros/fedora/onthespot.spec" ~/rpmbuild/SPECS/ >> "$log" 2>&1

  echo "Running rpmbuild..." >> "$log"
  rpmbuild -ba ~/rpmbuild/SPECS/onthespot.spec >> "$log" 2>&1
  
  cp ~/rpmbuild/RPMS/noarch/onthespot-*.noarch.rpm "$ROOT/build/dist/OnTheSpot.rpm" >> "$log" 2>&1
}

run_cleanup() {
  local log="$LOG_DIR/cleanup.log"
  rm -rf "$ROOT/__pycache__" "$ROOT/build/pyinstaller_work" "$ROOT/build"/*.spec "$ROOT/build/appimage_work" >> "$log" 2>&1
}

# ── Dispatcher ────────────────────────────────────────────────
run_step() {
  local step="$1"
  local start_time
  start_time=$(date +%s)

  print_dashboard "$step" "▘" "0"
  echo -e "  ${CYAN}Running: $(get_step_label "$step")${RESET}\033[K"
  echo -e "  ${DIM}Tail log: tail -f build/logs/linux/${step}.log${RESET}\033[K"
  echo -e "\033[K"

  rm -f "$STATE_DIR/$step.failed" "$STATE_DIR/$step.time"
  : > "$LOG_DIR/${step}.log"   # truncate log

  # Spin characters
  local spin_chars=("▘" "▝" "▗" "▖")
  local spin_count=${#spin_chars[@]}
  local idx=0

  set +e
  # Run step function in a background subshell
  ( set -e; "run_$step" ) >> "$LOG_DIR/${step}.log" 2>&1 &
  local pid=$!
  
  # Trap Ctrl-C to kill background process
  trap 'kill $pid 2>/dev/null; exit 1' INT TERM
  
  while kill -0 $pid 2>/dev/null; do
    local frame="${spin_chars[$idx]}"
    idx=$(( (idx + 1) % spin_count ))
    local elapsed=$(( $(date +%s) - start_time ))
    print_dashboard "$step" "$frame" "$elapsed"
    echo -e "  ${CYAN}Running: $(get_step_label "$step")${RESET}\033[K"
    echo -e "  ${DIM}Tail log: tail -f build/logs/linux/${step}.log${RESET}\033[K"
    echo -e "\033[K"
    sleep 0.1
  done
  
  # Reset trap
  trap - INT TERM
  wait $pid
  local status=$?
  set -e

  local duration=$(( $(date +%s) - start_time ))

  if [ $status -eq 0 ]; then
    echo "$duration" > "$STATE_DIR/$step.time"
    mark_done "$step"
    print_dashboard
    echo -e "  ${GREEN}✔ Done: $(get_step_label "$step") (${duration}s)${RESET}\033[K"
    echo -e "\033[K"
    sleep 0.5
  else
    mark_failed "$step"
    print_dashboard
    echo -e "\033[K\n  ${RED}✘ FAILED: $(get_step_label "$step") (${duration}s)${RESET}\033[K"
    echo -e "  ${DIM}Last 5 lines of build/logs/linux/${step}.log:${RESET}\033[K"
    tail -n 5 "$LOG_DIR/${step}.log" | sed 's/^/    /' | sed 's/$/\x1b[K/'
    echo -e "\033[K\n  ${DIM}See full log: build/logs/linux/${step}.log${RESET}\033[K"
    exit 1
  fi
}

# ── Main ──────────────────────────────────────────────────────
cd "$ROOT"

while [ $# -gt 0 ]; do
  case "$1" in
    --tarball)
      TARGET_TARBALL=1
      shift
      ;;
    --appimage)
      TARGET_APPIMAGE=1
      shift
      ;;
    --rpm)
      TARGET_RPM=1
      shift
      ;;
    --all)
      TARGET_TARBALL=1
      TARGET_APPIMAGE=1
      TARGET_RPM=1
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
      # If status is run, we must detect at least one target to represent N/A steps correctly.
      # If none specified, assume all.
      if [ "$TARGET_TARBALL" -eq 0 ] && [ "$TARGET_APPIMAGE" -eq 0 ] && [ "$TARGET_RPM" -eq 0 ]; then
        TARGET_TARBALL=1
        TARGET_APPIMAGE=1
        TARGET_RPM=1
      fi
      print_dashboard
      exit 0
      ;;
    --step)
      step="${2:-}"
      clear_step "$step"
      
      # Force make active for this run
      case "$step" in
        ffmpeg) TARGET_TARBALL=1 ;;
        build_wheel) TARGET_APPIMAGE=1 ;;
        pyinstaller) TARGET_TARBALL=1 ;;
        appimage) TARGET_APPIMAGE=1 ;;
        rpm) TARGET_RPM=1 ;;
      esac
      
      run_step "$step"
      print_dashboard
      exit 0
      ;;
    --help|-h)
      echo "Usage: $0 [option]"
      echo ""
      echo "Options:"
      echo "  (none)              Run all pending steps for all targets"
      echo "  --all               Build all targets (tarball, AppImage, RPM)"
      echo "  --tarball           Build Tarball target only"
      echo "  --appimage          Build AppImage target only"
      echo "  --rpm               Build RPM target only"
      echo "  --build-ffmpeg      Force download ffmpeg instead of copying from system"
      echo "  --reset             Clear all step state"
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

# If no target filter is selected, default to all
if [ "$TARGET_TARBALL" -eq 0 ] && [ "$TARGET_APPIMAGE" -eq 0 ] && [ "$TARGET_RPM" -eq 0 ]; then
  TARGET_TARBALL=1
  TARGET_APPIMAGE=1
  TARGET_RPM=1
fi

check_overwrite_dist() {
  local has_rebuildable=0
  if [ -d "$ROOT/build/dist" ]; then
    for name in "OnTheSpot.tar.gz" "onthespot-gui" "OnTheSpot-x86_64.AppImage" "OnTheSpot.rpm"; do
      if [ -e "$ROOT/build/dist/$name" ]; then
        has_rebuildable=1
        break
      fi
    done
  fi

  if [ "$has_rebuildable" -eq 1 ]; then
    local confirm=""
    if [ ! -t 0 ]; then
      confirm="y"
    else
      printf "\033[?25h"
      echo -e "${YELLOW}Warning: Build output directory 'build/dist/' contains existing build outputs that will be replaced.${RESET}"
      read -p "Overwrite and replace existing build outputs? (y/n): " confirm
      printf "\033[?25l"
    fi
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}Cleaning existing build outputs from build/dist/...${RESET}"
      for name in "OnTheSpot.tar.gz" "onthespot-gui" "OnTheSpot-x86_64.AppImage" "OnTheSpot.rpm"; do
        rm -f "$ROOT/build/dist/$name"
      done
      # Reset active steps to ensure a clean rebuild from scratch
      for s in "${STEPS[@]}"; do
        if is_step_active "$s"; then
          clear_step "$s"
        fi
      done
    else
      echo -e "${RED}Build aborted by user.${RESET}"
      exit 1
    fi
  fi
}

check_overwrite_dist

# Clear screen once at start of build if output is a TTY
if [ -t 1 ]; then
  clear
fi

echo -e "\n${BOLD}Starting OnTheSpot Linux build...${RESET}\n"
for step in "${STEPS[@]}"; do
  if step_done "$step"; then
    step_status "$step"
    if [ "$STATUS_VAL" = "na" ]; then
      echo -e "  ${DIM}— Skipping (not applicable for target):${RESET} $(get_step_label "$step")"
    else
      echo -e "  ${GREEN}✔ Skipping (already done):${RESET} $(get_step_label "$step")"
    fi
  else
    run_step "$step"
  fi
done

print_dashboard
echo -e "${BOLD}${GREEN}Build complete! Outputs in build/dist/${RESET}\n"
