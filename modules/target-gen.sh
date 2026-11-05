#!/usr/bin/env bash
set -euo pipefail
usage() {
cat <<'USAGE'
Usage:
  h4x-cli target-gen -p <port>[/protocol] -input-file <scan.nmap> [--output-file <file>]
  h4x-cli target-gen --list-ports -input-file <scan.nmap> [--output-file <file>]

Modes:
  -p, --port <port>           Generate a line-delimited target list for an open port
  -l, --list-ports            Display a table of the unique open ports found in the Nmap file
                              and how many hosts have each port open

Input and output:
  -i, -input-file, --input-file <file>
                              Nmap normal-output (.nmap) file
  -o, --output-file <file>    Custom output file
                              Target generation uses an automatic filename when omitted.
                              Port listing writes no file unless this option is supplied.
  --no-color                  Disable colored output
  -h, --help                  Show this help

Only entries whose state is exactly "open" are included. Closed, filtered,
open|filtered, and closed|filtered entries are ignored.
USAGE
}
PORT=""; INPUT=""; OUTPUT=""; LIST_PORTS=0; COLOR=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port) PORT="${2:-}"; shift 2 ;;
    -l|--list|--list-ports) LIST_PORTS=1; shift ;;
    --no-color) COLOR=0; shift ;;
    -i|-input-file|--input-file) INPUT="${2:-}"; shift 2 ;;
    -o|--output-file|-output-file) OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[!] Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -n "$INPUT" ]] || { echo "[!] -input-file is required" >&2; exit 1; }
[[ -f "$INPUT" ]] || { echo "[!] Input file not found: $INPUT" >&2; exit 1; }
if (( LIST_PORTS )) && [[ -n "$PORT" ]]; then
  echo "[!] --list-ports and --port are separate modes and cannot be used together" >&2
  exit 1
fi
if (( LIST_PORTS )); then
  if (( COLOR )) && [[ -t 1 ]]; then
    C_HDR=$'\e[1;36m'; C_PORT=$'\e[32m'; C_CNT=$'\e[33m'; C_BOR=$'\e[2m'; C_OK=$'\e[1;32m'; C_RST=$'\e[0m'
  else
    C_HDR=""; C_PORT=""; C_CNT=""; C_BOR=""; C_OK=""; C_RST=""
  fi
  # "<port>/<proto> <host count>" - each host counted once per port
  DATA="$(awk '
    /^Nmap scan report for / {ip=$NF; gsub(/[()]/,"",ip); next}
    $1 ~ /^[0-9]+\/(tcp|udp|sctp)$/ && $2 == "open" {
      key = ip SUBSEP $1
      if (!(key in seen)) { seen[key]=1; count[$1]++ }
    }
    END { for (p in count) print p, count[p] }
  ' "$INPUT" | sort -t/ -k1,1n -k2,2)"
  if [[ -z "$DATA" ]]; then
    echo "[+] Unique open ports: 0"
    echo "[-] No ports in the strict open state were found."
    if [[ -n "$OUTPUT" ]]; then
      { echo "Unique open ports: 0"; } > "$OUTPUT"
      echo "[+] Port inventory written to: ${OUTPUT}"
    fi
    exit 2
  fi
  COUNT="$(wc -l <<< "$DATA" | tr -d ' ')"
  TOTAL="$(awk '{s+=$2} END{print s}' <<< "$DATA")"
  W1=12; W2=12
  render() {  # args: border header port count ok reset (empty strings = no color)
    local bor=$1 hdr=$2 prt=$3 cnt=$4 ok=$5 rst=$6 line
    line="+$(printf '%*s' $((W1+2)) '' | tr ' ' '-')+$(printf '%*s' $((W2+2)) '' | tr ' ' '-')+"
    echo "${ok}[+] Unique open ports: ${COUNT}${rst}"
    echo
    echo "${bor}${line}${rst}"
    printf '%s|%s %s%-*s%s %s|%s %s%*s%s %s|%s\n' "$bor" "$rst" "$hdr" $W1 "PORT" "$rst" "$bor" "$rst" "$hdr" $W2 "HOST COUNT" "$rst" "$bor" "$rst"
    echo "${bor}${line}${rst}"
    while read -r p c; do
      printf '%s|%s %s%-*s%s %s|%s %s%*s%s %s|%s\n' "$bor" "$rst" "$prt" $W1 "$p" "$rst" "$bor" "$rst" "$cnt" $W2 "$c" "$rst" "$bor" "$rst"
    done <<< "$DATA"
    echo "${bor}${line}${rst}"
    printf '%s|%s %-*s %s|%s %*s %s|%s\n' "$bor" "$rst" $W1 "TOTAL" "$bor" "$rst" $W2 "$TOTAL" "$bor" "$rst"
    echo "${bor}${line}${rst}"
  }
  render "$C_BOR" "$C_HDR" "$C_PORT" "$C_CNT" "$C_OK" "$C_RST"
  if [[ -n "$OUTPUT" ]]; then
    render "" "" "" "" "" "" > "$OUTPUT"
    echo "[+] Port inventory written to: ${OUTPUT}"
  fi
  exit 0
fi
[[ -n "$PORT" ]] || { echo "[!] Supply --port or --list-ports" >&2; usage >&2; exit 1; }
PORTNUM="${PORT%%/*}"; PROTO=""; [[ "$PORT" == */* ]] && PROTO="${PORT#*/}"
[[ "$PORTNUM" =~ ^[0-9]+$ ]] && (( PORTNUM >= 1 && PORTNUM <= 65535 )) || { echo "[!] Invalid port: $PORT" >&2; exit 1; }
[[ -z "$PROTO" || "$PROTO" =~ ^(tcp|udp|sctp)$ ]] || { echo "[!] Invalid protocol: $PROTO" >&2; exit 1; }
if [[ -z "$OUTPUT" ]]; then
  DIR="$(dirname "$INPUT")"; BASE="$(basename "$INPUT")"; BASE="${BASE%.nmap}"
  SUFFIX="$PORTNUM"; [[ -n "$PROTO" ]] && SUFFIX="${PORTNUM}${PROTO}"
  while :; do
    RAND=$(( (RANDOM * 32768 + RANDOM) % 90000 + 10000 ))
    OUTPUT="${DIR}/${BASE}-${SUFFIX}-targets-${RAND}.txt"
    [[ ! -e "$OUTPUT" ]] && break
  done
fi
RESULTS="$(awk -v port="$PORTNUM" -v proto="$PROTO" '
/^Nmap scan report for / {ip=$NF; gsub(/[()]/,"",ip); next}
$1 ~ /^[0-9]+\/(tcp|udp|sctp)$/ {
  split($1,p,"/")
  if (p[1]==port && (proto=="" || p[2]==proto) && $2=="open" && ip!="") print ip
}' "$INPUT" | sort -u -V)"
[[ -n "$RESULTS" ]] || { echo "[-] No hosts found with port ${PORT} open in ${INPUT}. No file written."; exit 2; }
printf '%s\n' "$RESULTS" > "$OUTPUT"
echo "[+] $(wc -l < "$OUTPUT") host(s) with port ${PORT} open"
echo "[+] Targets written to: ${OUTPUT}"
