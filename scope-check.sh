#!/usr/bin/env bash
set -uo pipefail
usage() {
cat <<'USAGE'
Usage: h4x-cli scope-check -input-file <cidrs.txt> [options]
Options:
  -i, -input-file, --input-file <file>  IP addresses/CIDRs to inspect
  -o, --output-file <file>              CSV report path
  --ptr-sample <n>                      PTR lookups per range (default: 8; 0 disables)
  --delay <seconds>                     Delay between WHOIS queries (default: 1)
  --no-color                            Disable colored output
  -c, --client <name>                   Accepted for backward compatibility; not evaluated
  -a, --alias <name>                    Accepted for backward compatibility; not evaluated
  -d, --domain <domain>                 Accepted for backward compatibility; not evaluated
  --max-segments <n>                    Accepted for backward compatibility
  -h, --help                            Show this help
This module collects passive evidence only. It does not calculate a confidence
score, likelihood, ownership verdict, or recommendation.
USAGE
}
INPUT=""; OUTPUT=""; PTR_SAMPLE=8; DELAY=1; COLOR=1
while [[ $# -gt 0 ]]; do
 case "$1" in
  -i|-input-file|--input-file) INPUT="${2:-}"; shift 2;;
  -o|-output-file|--output-file) OUTPUT="${2:-}"; shift 2;;
  --ptr-sample) PTR_SAMPLE="${2:-}"; shift 2;;
  --delay) DELAY="${2:-}"; shift 2;;
  --no-color) COLOR=0; shift;;
  -c|--client|-a|--alias|-d|--domain|--max-segments) shift 2;;
  -h|--help) usage; exit 0;;
  *) echo "[!] Unknown option: $1" >&2; exit 1;;
 esac
done
[[ -n "$INPUT" ]] || { echo "[!] --input-file is required" >&2; exit 1; }
[[ -f "$INPUT" ]] || { echo "[!] Input file not found: $INPUT" >&2; exit 1; }
[[ "$PTR_SAMPLE" =~ ^[0-9]+$ ]] || { echo "[!] --ptr-sample must be a non-negative integer" >&2; exit 1; }
[[ "$DELAY" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "[!] --delay must be a non-negative number" >&2; exit 1; }
for b in whois dig python3; do command -v "$b" >/dev/null || { echo "[!] Missing dependency: $b" >&2; exit 1; }; done
if [[ -z "$OUTPUT" ]]; then
 DIR="$(dirname "$INPUT")"; BASE="$(basename "$INPUT")"; BASE="${BASE%.*}"
 while :; do RAND=$(( (RANDOM*32768+RANDOM)%90000+10000 )); OUTPUT="$DIR/${BASE}-scope-check-${RAND}.csv"; [[ ! -e "$OUTPUT" ]] && break; done
fi
csv(){ local s=${1//\"/\"\"}; printf '"%s"' "$s"; }
echo 'input_range,address_type,registered_range,registered_org,netname,whois_email_domains,asn,as_name,ptr_sampled,ptr_resolved,ptr_examples' > "$OUTPUT"
printf '%-22s %-14s %-42s %s\n' "INPUT" "TYPE" "REGISTERED ORG" "ASN / AS NAME"
printf '%.0s-' {1..110}; echo
while IFS= read -r raw || [[ -n "$raw" ]]; do
 line="$(sed -E 's/#.*//;s/^[[:space:]]+|[[:space:]]+$//g' <<< "$raw")"; [[ -n "$line" ]] || continue
 [[ "$line" == */* ]] || line="$line/32"; ip="${line%/*}"
 read -r addr_type sample_list < <(python3 - "$line" "$PTR_SAMPLE" <<'PY'
import ipaddress,sys
n=ipaddress.ip_network(sys.argv[1],strict=False); count=int(sys.argv[2])
kind='private/reserved' if (n.is_private or n.is_reserved or n.is_loopback or n.is_link_local) else 'public'
if count <= 0: samples=[]
else:
 first=int(n.network_address); last=int(n.broadcast_address)
 if n.version==4 and n.num_addresses>2: first+=1; last-=1
 total=max(0,last-first+1); take=min(count,total)
 samples=[] if take==0 else [str(ipaddress.ip_address(first + (0 if take==1 else round(i*(total-1)/(take-1))))) for i in range(take)]
print(kind, ','.join(samples))
PY
 )
 WHOIS=""; org=""; range=""; net=""; emails=""; asn=""; asname=""
 if [[ "$addr_type" == "public" ]]; then
  sleep "$DELAY"; WHOIS="$(timeout 30 whois "$ip" 2>/dev/null || true)"
  org="$(awk -F: 'BEGIN{IGNORECASE=1}/^(CustName|OrgName|org-name|owner|descr):/{sub(/^[^:]*:[ \t]*/,"");print;exit}' <<< "$WHOIS")"
  range="$(awk -F: 'BEGIN{IGNORECASE=1}/^(NetRange|inetnum|IPv4 Address):/{sub(/^[^:]*:[ \t]*/,"");print;exit}' <<< "$WHOIS")"
  net="$(awk -F: 'BEGIN{IGNORECASE=1}/^netname:/{sub(/^[^:]*:[ \t]*/,"");print;exit}' <<< "$WHOIS")"
  emails="$(grep -Eio '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+' <<< "$WHOIS" | sed 's/.*@//' | tr 'A-Z' 'a-z' | sort -u | paste -sd';' -)"
  rev="$(awk -F. '{print $4"."$3"."$2"."$1}' <<< "$ip")"; asraw="$(dig +short +time=3 +tries=1 TXT "$rev.origin.asn.cymru.com" 2>/dev/null | head -1 | tr -d '"')"
  asnum="$(awk -F'|' '{gsub(/ /,"",$1);print $1}' <<< "$asraw")"
  if [[ -n "$asnum" ]]; then asn="AS${asnum}"; asname="$(dig +short +time=3 +tries=1 TXT "$asn.asn.cymru.com" 2>/dev/null | head -1 | tr -d '"' | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$5);print $5}')"; fi
 fi
 ptr_count=0; ptr_resolved=0; ptr_examples=""
 if [[ -n "$sample_list" ]]; then
  IFS=',' read -ra samples <<< "$sample_list"; ptr_count=${#samples[@]}
  for sample in "${samples[@]}"; do ptr="$(dig +short +time=2 +tries=1 -x "$sample" 2>/dev/null | head -1 | sed 's/\.$//' || true)"; if [[ -n "$ptr" ]]; then ((ptr_resolved++)); ptr_examples+="${ptr_examples:+;}${sample}=${ptr}"; fi; done
 fi
 printf '%-22s %-14s %-42s %s %s\n' "$line" "$addr_type" "${org:-unknown}" "${asn:--}" "${asname:--}"
 { csv "$line"; printf ','; csv "$addr_type"; printf ','; csv "$range"; printf ','; csv "$org"; printf ','; csv "$net"; printf ','; csv "$emails"; printf ','; csv "$asn"; printf ','; csv "$asname"; printf ',%s,%s,' "$ptr_count" "$ptr_resolved"; csv "$ptr_examples"; echo; } >> "$OUTPUT"
done < "$INPUT"
echo "[+] Evidence report written to: $OUTPUT"
echo "[*] No ownership verdict or confidence score was calculated."
