#!/usr/bin/env bash
set -euo pipefail
usage() {
cat <<'USAGE'
Usage:
  h4x-cli masscan-to-csv --scope <scope.txt> --input-file <masscan.oL> [options]
Required:
  -s, --scope <file>                    Authorized IPv4/IPv6 addresses or CIDRs
  -i, -input-file, --input-file <file>  Masscan -oL output
Optional:
  -e, --exclusions <file>               IPv4/IPv6 addresses or CIDRs to omit
  -o, --output-file <file>              Custom CSV filename
  -h, --help                            Show this help
The CSV contains every in-scope, non-excluded address, including hosts with zero
open ports. Open ports are reported as protocol/port entries.
USAGE
}
SCOPE=""; INPUT=""; EXCLUSIONS=""; OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--scope|--scope-file) SCOPE="${2:-}"; shift 2 ;;
    -i|-input-file|--input-file) INPUT="${2:-}"; shift 2 ;;
    -e|--exclusions|--exclusions-file) EXCLUSIONS="${2:-}"; shift 2 ;;
    -o|-output-file|--output-file) OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[!] Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -f "$SCOPE" ]] || { echo "[!] Scope file not found: $SCOPE" >&2; exit 1; }
[[ -f "$INPUT" ]] || { echo "[!] Masscan input file not found: $INPUT" >&2; exit 1; }
[[ -z "$EXCLUSIONS" || -f "$EXCLUSIONS" ]] || { echo "[!] Exclusions file not found: $EXCLUSIONS" >&2; exit 1; }
if [[ -z "$OUTPUT" ]]; then
  DIR="$(dirname "$INPUT")"; BASE="$(basename "$INPUT")"; BASE="${BASE%.*}"
  while :; do RAND=$(( (RANDOM * 32768 + RANDOM) % 90000 + 10000 )); OUTPUT="${DIR}/${BASE}-masscan-${RAND}.csv"; [[ ! -e "$OUTPUT" ]] && break; done
fi
python3 - "$SCOPE" "$INPUT" "$EXCLUSIONS" "$OUTPUT" <<'PY'
import csv, ipaddress, sys
scope_path, masscan_path, exclusions_path, output_path = sys.argv[1:]
def read_networks(path):
    nets=[]
    if not path: return nets
    with open(path, encoding='utf-8', errors='replace') as f:
        for number, raw in enumerate(f, 1):
            value=raw.split('#',1)[0].strip()
            if not value: continue
            try: nets.append(ipaddress.ip_network(value, strict=False))
            except ValueError as e: print(f"[~] Ignoring invalid entry {path}:{number}: {value} ({e})", file=sys.stderr)
    return nets
scope=read_networks(scope_path); exclusions=read_networks(exclusions_path)
if not scope: raise SystemExit('[!] Scope file contains no valid addresses or CIDRs')
def covered(ip, nets): return any(ip.version == n.version and ip in n for n in nets)
ports={}
with open(masscan_path, encoding='utf-8', errors='replace') as f:
    for raw in f:
        parts=raw.split()
        if len(parts) < 5 or parts[0] != 'open': continue
        proto, port, text_ip = parts[1], parts[2], parts[3]
        try: ip=ipaddress.ip_address(text_ip)
        except ValueError: continue
        if covered(ip, scope) and not covered(ip, exclusions):
            ports.setdefault(ip, set()).add((proto, int(port)))
addresses=[]
for net in scope:
    iterable = net.hosts() if net.version == 4 and net.prefixlen < 31 else iter(net)
    for ip in iterable:
        if not covered(ip, exclusions): addresses.append(ip)
addresses=sorted(set(addresses), key=lambda x:(x.version, int(x)))
with open(output_path, 'w', newline='', encoding='utf-8') as f:
    writer=csv.writer(f); writer.writerow(['IP Address','Open Port Count','Open Ports'])
    for ip in addresses:
        entries=sorted(ports.get(ip,set()), key=lambda x:(x[1],x[0]))
        writer.writerow([str(ip), len(entries), ' '.join(f'{p}/{n}' for p,n in entries)])
print(f'[+] {len(addresses)} in-scope, non-excluded address(es) written')
print(f'[+] CSV written to: {output_path}')
PY
