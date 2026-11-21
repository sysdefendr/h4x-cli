#!/usr/bin/env bash
set -euo pipefail
usage() {
cat <<'USAGE'
Usage:
  h4x-cli kerb-target-gen -input-file <kerbrute-output.txt> [--output-file <file>]
Options:
  -i, -input-file, --input-file <file>  Kerbrute userenum console output
  -o, -output-file, --output-file <file> Custom output filename
  -h, --help                            Show this help
Only lines containing "[+] VALID USERNAME:" are included. The domain suffix
beginning with @ is removed. Output is unique and line-delimited.
USAGE
}
INPUT=""; OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|-input-file|--input-file) INPUT="${2:-}"; shift 2 ;;
    -o|-output-file|--output-file) OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[!] Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -n "$INPUT" ]] || { echo "[!] --input-file is required" >&2; exit 1; }
[[ -f "$INPUT" ]] || { echo "[!] Input file not found: $INPUT" >&2; exit 1; }
if [[ -z "$OUTPUT" ]]; then
  DIR="$(dirname "$INPUT")"; BASE="$(basename "$INPUT")"; BASE="${BASE%.*}"
  while :; do
    RAND=$(( (RANDOM * 32768 + RANDOM) % 90000 + 10000 ))
    OUTPUT="${DIR}/${BASE}-kerb-targets-${RAND}.txt"
    [[ ! -e "$OUTPUT" ]] && break
  done
fi
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
awk '
  /\[\+\][[:space:]]+VALID USERNAME:/ {
    line=$0
    sub(/^.*VALID USERNAME:[[:space:]]*/, "", line)
    sub(/[[:space:]].*$/, "", line)
    sub(/@.*/, "", line)
    if (line != "" && !seen[line]++) print line
  }
' "$INPUT" > "$TMP"
[[ -s "$TMP" ]] || { echo "[-] No valid usernames found. No file written."; exit 2; }
mv "$TMP" "$OUTPUT"; trap - EXIT
echo "[+] $(wc -l < "$OUTPUT" | tr -d ' ') username(s) extracted"
echo "[+] Targets written to: $OUTPUT"
