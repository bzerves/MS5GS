#!/bin/bash

# 🔧 Config
TMP_LOG="$HOME/.enb_status.log"
JOURNAL_LINES=5000

# 🎨 Color Constants
COLOR_ORANGE="\e[38;5;214m"
COLOR_LIGHT_BLUE="\e[38;5;117m"
COLOR_DARK_BLUE="\e[38;5;27m"
COLOR_WHITE="\e[1;37m"
COLOR_RESET="\e[0m"

# Source the logo
source "$(dirname "$0")/logo.sh"

function render_screen() {
  clear
  draw_logo
  echo -e "${COLOR_WHITE}\033[1m📶 eNB STATUS DASHBOARD${COLOR_RESET}"
  echo

  # Header
  printf " %-4s | %-15s | %-9s | %-9s\n" \
    "No." "IP Address" "Status" "Ping Time"
  printf -- "------+-----------------+-----------+-----------\n"

  local counter=1
  echo "$latest" | while read -r ip status; do
    ping_output=$(ping -c 1 -W 1 "$ip" 2>/dev/null)
    if echo "$ping_output" | grep -q 'time='; then
      ping_time=$(echo "$ping_output" | grep 'time=' | sed -n 's/.*time=\([0-9.]*\) ms.*/\1 ms/p')
    else
      ping_time="N/A"
    fi

    # Row
    printf " %-4s | %-15s | %-9s | %-9s\n" \
      "$counter" "$ip" "$status" "$ping_time"

    ((counter++))
  done

  echo
  echo -e "${COLOR_WHITE}PRESS Q TO QUIT${COLOR_RESET}"
  echo
}

# 🌀 Main loop
while true; do
  sudo journalctl -u open5gs-mmed -n "$JOURNAL_LINES" | \
  grep -E 'eNB-S1 accepted\[|eNB-S1\[.*connection refused|eNB-S1\[.*max_num_of_ostreams' | \
  sed -n -E 's/.*eNB-S1 accepted\[([0-9\.]+)\].*/\1 ATTACHED/p; s/.*eNB-S1\[([0-9\.]+)\] connection refused.*/\1 DETACHED/p; s/.*eNB-S1\[([0-9\.]+)\] max_num_of_ostreams.*/\1 ATTACHED/p' \
  > "$TMP_LOG"

  latest=$(tac "$TMP_LOG" | awk '!seen[$1]++ {print $1, $2}')

  render_screen

  read -n 1 input
  case "$input" in
    q) exit 0 ;;
    Q) exit 0 ;;
  esac
done