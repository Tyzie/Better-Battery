#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

PLUGIN_ID="tyzie.better-battery-fixed"

resolve_user() {
  local u
  for u in "${SUDO_USER:-}" "${USER:-}"; do
    [ -n "$u" ] && [ "$u" != "root" ] && { echo "$u"; return; }
  done
  if [ "$(id -u)" = "0" ]; then
    u=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$3!="root" && $3!="" {print $3; exit}')
    [ -n "$u" ] && { echo "$u"; return; }
    u=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')
    [ -n "$u" ] && { echo "$u"; return; }
  fi
  id -un
}

USER_NAME="$(resolve_user)"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[ -n "$USER_HOME" ] || USER_HOME="/home/$USER_NAME"
# systemd-sleep runs as root with HOME=/root; prefer resolved user dirs.
if [ "$(id -u)" = "0" ] || [[ "${XDG_STATE_HOME:-}" == /root/* ]] || [[ "${HOME:-}" == /root ]]; then
  STATE_DIR="$USER_HOME/.local/state/omarchy/$PLUGIN_ID"
  CONFIG_DIR="$USER_HOME/.config/omarchy/$PLUGIN_ID"
else
  STATE_DIR="${XDG_STATE_HOME:-$USER_HOME/.local/state}/omarchy/$PLUGIN_ID"
  CONFIG_DIR="${XDG_CONFIG_HOME:-$USER_HOME/.config}/omarchy/$PLUGIN_ID"
fi
RUNTIME_DIR="/run/user/$(id -u "$USER_NAME" 2>/dev/null || echo 1000)/$PLUGIN_ID"
SLEEP_LOG="$STATE_DIR/sleep.log"
PENDING_SLEEP="$STATE_DIR/pending-sleep.json"
CHARGE_LOG="$STATE_DIR/charge.log"
PENDING_CHARGE="$STATE_DIR/pending-charge.json"
CHARGE_STATE="$STATE_DIR/charge-state"
AUTO_MODE_FILE="$STATE_DIR/auto-mode"
PROFILE_MODE_FILE="$STATE_DIR/profile-mode"
PROFILE_HELPER="/usr/local/libexec/tyzie-better-battery-fixed-profile"
PROFILE_SUDOERS="/etc/sudoers.d/tyzie-better-battery-fixed"
PROFILE_HELPER_MARKER="$STATE_DIR/profile-helper-installed"

mkdir -p "$STATE_DIR" "$CONFIG_DIR" 2>/dev/null || true
mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
chown "$USER_NAME":"$(id -gn "$USER_NAME" 2>/dev/null || echo "$USER_NAME")" "$STATE_DIR" "$CONFIG_DIR" 2>/dev/null || true

json_escape() {
  jq -Rn --arg s "$1" '$s'
}

have() { command -v "$1" >/dev/null 2>&1; }

battery_path() {
  local d
  for d in /sys/class/power_supply/BAT*; do
    [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

ac_online() {
  local a
  for a in /sys/class/power_supply/A{C,ADP,M}*/online /sys/class/power_supply/AC*/online; do
    [ -r "$a" ] && { cat "$a"; return 0; }
  done
  echo 0
}

read_sys() {
  local f="$1" def="${2:-}"
  [ -r "$f" ] && cat "$f" || printf '%s' "$def"
}

energy_uwh() {
  local bat="$1" key="$2" charge_key="$3"
  local e v
  e=$(read_sys "$bat/$key" 0)
  if [ "${e:-0}" -gt 0 ]; then
    echo "$e"
    return
  fi
  v=$(read_sys "$bat/voltage_now" 0)
  [ "${v:-0}" -gt 0 ] || { echo 0; return; }
  local c
  c=$(read_sys "$bat/$charge_key" 0)
  awk -v c="$c" -v v="$v" 'BEGIN{printf "%.0f", c*v/1000000}'
}

power_uw() {
  local bat="$1"
  local p
  p=$(read_sys "$bat/power_now" 0)
  if [ "${p:-0}" -gt 0 ]; then
    echo "${p#-}"
    return
  fi
  local v c
  v=$(read_sys "$bat/voltage_now" 0)
  c=$(read_sys "$bat/current_now" 0)
  [ "${c:-0}" -eq 0 ] && c=$(read_sys "$bat/current_avg" 0)
  c=${c#-}
  if [ "${v:-0}" -gt 0 ] && [ "${c:-0}" -gt 0 ]; then
    awk -v c="$c" -v v="$v" 'BEGIN{printf "%.0f", c*v/1000000}'
  else
    echo 0
  fi
}

fmt_iso_now() { date -Iseconds; }

profile_governor() {
  read_sys /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor unknown
}

profile_boost() {
  read_sys /sys/devices/system/cpu/cpufreq/boost -1
}

profile_helper_installed() {
  [ -f "$PROFILE_HELPER_MARKER" ]
}

profile_mode() {
  local mode
  mode=$(read_sys "$PROFILE_MODE_FILE" "normal")
  case "$mode" in
    econom|normal|power|auto) echo "$mode" ;;
    *) echo normal ;;
  esac
}

profile_effective() {
  local mode="$1" ac="$2"
  if [ "$mode" = "auto" ]; then
    [ "$ac" = "1" ] && echo power || echo econom
  else
    echo "$mode"
  fi
}

profile_targets() {
  local mode="$1"
  case "$mode" in
    econom) echo "powersave 0" ;;
    normal) echo "powersave 1" ;;
    power) echo "performance 1" ;;
    *) echo "powersave 1" ;;
  esac
}

finish_charge_session() {
  local cap="$1" energy="$2" iso="$3" now="$4" status="$5"
  local pre pre_ts pre_cap pre_en dur cap_gain wh_gain rate
  [ -r "$PENDING_CHARGE" ] || return 0
  pre=$(cat "$PENDING_CHARGE")
  pre_ts=$(jq -r '.ts // 0' <<<"$pre")
  pre_cap=$(jq -r '.cap // 0' <<<"$pre")
  pre_en=$(jq -r '.energy // 0' <<<"$pre")
  dur=$((now - pre_ts))
  [ "$dur" -lt 0 ] && dur=0
  if [ "$dur" -ge "${CHARGE_MIN_SEC:-30}" ]; then
    cap_gain=$(awk -v a="$pre_cap" -v b="$cap" 'BEGIN{d=b-a; if(d<0)d=0; printf "%.2f", d}')
    wh_gain=$(awk -v a="$pre_en" -v b="$energy" 'BEGIN{d=(b-a)/1000000; if(d<0)d=0; printf "%.3f", d}')
    rate=$(awk -v wh="$wh_gain" -v s="$dur" 'BEGIN{if(s>0) printf "%.3f", wh*3600/s; else print "0.000"}')
    jq -cn \
      --arg startIso "$(jq -r '.iso // ""' <<<"$pre")" \
      --arg endIso "$iso" \
      --argjson durationSec "$dur" \
      --argjson startCap "$pre_cap" \
      --argjson endCap "$cap" \
      --argjson capGain "$cap_gain" \
      --argjson whGain "$wh_gain" \
      --argjson avgRateW "$rate" \
      --arg status "$status" \
      '{startIso:$startIso,endIso:$endIso,durationSec:$durationSec,startCap:$startCap,endCap:$endCap,capGain:$capGain,whGain:$whGain,avgRateW:$avgRateW,status:$status}' >> "$CHARGE_LOG"
  fi
  rm -f "$PENDING_CHARGE"
}

track_charge_session() {
  local ac="$1" cap="$2" energy="$3" status="$4" full="${5:-0}"
  local prev now iso state
  prev=$(read_sys "$CHARGE_STATE" "")
  now=$(date +%s)
  iso=$(date -Iseconds)

  if [ "$ac" = "1" ] && [ "$full" = "1" ]; then
    state=2
  elif [ "$ac" = "1" ]; then
    state=1
  else
    state=0
  fi

  if [ "$state" = "1" ] && [ "$prev" != "1" ]; then
    jq -cn --argjson ts "$now" --arg iso "$iso" --argjson cap "$cap" --argjson energy "$energy" \
      --arg status "$status" \
      '{ts:$ts,iso:$iso,cap:$cap,energy:$energy,status:$status}' > "$PENDING_CHARGE"
  elif [ "$state" = "0" ] && [ "$prev" = "1" ]; then
    finish_charge_session "$cap" "$energy" "$iso" "$now" "$status"
  elif [ "$state" = "2" ] && [ "$prev" = "1" ]; then
    finish_charge_session "$cap" "$energy" "$iso" "$now" "$status"
  fi
  printf '%s' "$state" > "$CHARGE_STATE"
}
