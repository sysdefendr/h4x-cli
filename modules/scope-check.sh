#!/usr/bin/env bash
set -uo pipefail
usage() {
cat <<'USAGE'
Usage: h4x-cli scope-check -c "<client name>" -input-file <cidrs.txt> [options]

Required:
  -c, --client <name>          Client legal/common name
  -i, -input-file, --input-file <file>

Optional:
  -a, --alias <name>           Additional client name, brand, or subsidiary (repeatable)
  -d, --domain <domain>        Client-owned domain (repeatable)
  -o, --output-file <file>     CSV report path
  --ptr-sample <n>             PTR lookups per range (default: 8; 0 disables)
  --delay <seconds>            Delay between WHOIS queries (default: 1)
  --max-segments <n>           Retained for command compatibility (default: 64)
  --no-color                   Disable colored output
  -h, --help                   Show this help

Likelihood is a score from 0-100 estimating whether the public range is
registered to or controlled by the named client.
USAGE
}
CLIENT=""; INPUT=""; OUTPUT=""; PTR_SAMPLE=8; DELAY=1; MAX_SEG=64; COLOR=1; ALIASES=(); DOMAINS=()
while [[ $# -gt 0 ]]; do
 case "$1" in
  -c|--client) CLIENT="${2:-}"; shift 2;;
  -i|-input-file|--input-file) INPUT="${2:-}"; shift 2;;
  -o|-output-file|--output-file) OUTPUT="${2:-}"; shift 2;;
  -a|--alias) ALIASES+=("${2:-}"); shift 2;;
  -d|--domain) DOMAINS+=("$(tr 'A-Z' 'a-z' <<< "${2:-}")"); shift 2;;
  --ptr-sample) PTR_SAMPLE="${2:-}"; shift 2;;
  --delay) DELAY="${2:-}"; shift 2;;
  --max-segments) MAX_SEG="${2:-}"; shift 2;;
  --no-color) COLOR=0; shift;;
  -h|--help) usage; exit 0;;
  *) echo "[!] Unknown option: $1" >&2; exit 1;;
 esac
done
[[ -n "$CLIENT" ]] || { echo "[!] --client is required" >&2; exit 1; }
[[ -f "$INPUT" ]] || { echo "[!] Input file not found: $INPUT" >&2; exit 1; }
for b in whois dig awk; do command -v "$b" >/dev/null || { echo "[!] Missing dependency: $b (Kali: sudo apt install whois dnsutils)" >&2; exit 1; }; done
if [[ -z "$OUTPUT" ]]; then
 DIR="$(dirname "$INPUT")"; BASE="$(basename "$INPUT")"; BASE="${BASE%.*}"
 while :; do RAND=$(( (RANDOM*32768+RANDOM)%90000+10000 )); OUTPUT="$DIR/${BASE}-scope-check-${RAND}.csv"; [[ ! -e "$OUTPUT" ]] && break; done
fi
if (( COLOR )) && [[ -t 1 ]]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; DIM=$'\e[2m'; N=$'\e[0m'; else R="";G="";Y="";DIM="";N="";fi
normalize(){ tr 'A-Z' 'a-z' <<< "$1" | sed -E 's/[^a-z0-9]+/ /g;s/\b(inc|incorporated|llc|ltd|limited|corp|corporation|company|the|and|group|holdings|services|global)\b/ /g;s/ +/ /g;s/^ | $//g'; }
TOKENS="$(normalize "$CLIENT")"; for a in "${ALIASES[@]+"${ALIASES[@]}"}"; do TOKENS+=" $(normalize "$a")"; done
csv(){ local s=${1//\"/\"\"}; printf '"%s"' "$s"; }
PROVIDER_RE='amazon|aws|microsoft|azure|google|cloudflare|akamai|fastly|oracle|digitalocean|linode|ovh|hetzner|rackspace|godaddy|vultr|leaseweb|cogent|zayo|lumen|centurylink|level 3|verizon|comcast|charter|spectrum|equinix|imperva|zscaler|github|heroku|netlify|vercel'
echo 'input_range,registered_range,registered_org,netname,whois_email_domains,asn,as_name,ptr_sampled,ptr_client_matches,ptr_examples,likelihood_client,verdict,reasons' > "$OUTPUT"
printf '%-20s %-38s %10s  %s\n' "INPUT" "REGISTERED ORG" "LIKELIHOOD" "VERDICT"; printf '%.0s-' {1..100}; echo
while IFS= read -r raw || [[ -n "$raw" ]]; do
 line="$(sed -E 's/#.*//;s/^[[:space:]]+|[[:space:]]+$//g' <<< "$raw")"; [[ -n "$line" ]] || continue
 [[ "$line" == */* ]] || line="$line/32"; ip="${line%/*}"
 if [[ "$ip" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
  verdict="PRIVATE / RESERVED"
  printf '%-20s %-38s %10s  %s\n\n' "$line" "-" "-" "${DIM}${verdict}${N}"
  { csv "$line"; printf ',,,,,,,,0,0,,,"%s","%s"\n' "$verdict" "Private or reserved space; verify through the client asset inventory"; } >> "$OUTPUT"
  continue
 fi
 sleep "$DELAY"; WHOIS="$(timeout 30 whois "$ip" 2>/dev/null)"
 org="$(awk -F: 'BEGIN{IGNORECASE=1}/^(CustName|OrgName|org-name|owner|descr):/{sub(/^[^:]*:[ \t]*/,"");print;exit}' <<< "$WHOIS")"
 range="$(awk -F: 'BEGIN{IGNORECASE=1}/^(NetRange|inetnum|IPv4 Address):/{sub(/^[^:]*:[ \t]*/,"");print;exit}' <<< "$WHOIS")"
 net="$(awk -F: 'BEGIN{IGNORECASE=1}/^netname:/{sub(/^[^:]*:[ \t]*/,"");print;exit}' <<< "$WHOIS")"
 emails="$(grep -Eio '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+' <<< "$WHOIS" | sed 's/.*@//' | tr 'A-Z' 'a-z' | sort -u | paste -sd';' -)"
 rev="$(awk -F. '{print $4"."$3"."$2"."$1}' <<< "$ip")"; asraw="$(dig +short +time=3 +tries=1 TXT "$rev.origin.asn.cymru.com" 2>/dev/null | head -1 | tr -d '"')"
 asnum="$(awk -F'|' '{gsub(/ /,"",$1);print $1}' <<< "$asraw")"; asn=""; asname=""
 if [[ -n "$asnum" ]]; then asn="AS${asnum}"; asname="$(dig +short +time=3 +tries=1 TXT "$asn.asn.cymru.com" 2>/dev/null | head -1 | tr -d '"' | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$5);print $5}')"; fi
 hay="$(normalize "$org $net $asname")"; score=0; reasons=()
 for t in $TOKENS; do [[ ${#t} -ge 3 && " $hay " == *" $t "* ]] && score=$((score+25)); done
 client_norm="$(normalize "$CLIENT")"; org_norm="$(normalize "$org")"
 [[ -n "$org_norm" && "$org_norm" == *"$client_norm"* ]] && { score=$((score+40)); reasons+=("Registrant organization matches client"); }
 for d in "${DOMAINS[@]+"${DOMAINS[@]}"}"; do [[ ";$emails;" == *";$d;"* ]] && { score=$((score+20)); reasons+=("WHOIS email matches client domain"); }; done
 ptrn=0; ptrh=0; ptre=""
 if (( PTR_SAMPLE > 0 )); then
  ptr="$(dig +short +time=2 +tries=1 -x "$ip" 2>/dev/null | head -1 | tr 'A-Z' 'a-z')"
  if [[ -n "$ptr" ]]; then ptrn=1; ptre="$ip=$ptr"; for d in "${DOMAINS[@]+"${DOMAINS[@]}"}"; do [[ "$ptr" == *"$d"* ]] && ptrh=1; done; ((ptrh)) && { score=$((score+20)); reasons+=("PTR references client"); }; fi
 fi
 ((score>100)) && score=100
 if ((score>=70)); then verdict="LIKELY CLIENT"; color=$G
 elif ((score>=40)); then verdict="POSSIBLE - VERIFY"; color=$Y
 elif grep -Eqi "$PROVIDER_RE" <<< "$org $net"; then verdict="PROVIDER SPACE - VERIFY"; color=$Y; reasons+=("Provider registration requires client attestation")
 else verdict="LIKELY THIRD PARTY"; color=$R; reasons+=("Registration does not match client"); fi
 reason="$(IFS='; '; echo "${reasons[*]}")"
 printf '%-20s %-38s %10s  %s\n' "$line" "${org:-unknown}" "$score" "${color}${verdict}${N}"
 [[ -n "$asn" ]] && printf '%-20s %s %s | netname: %s | registered: %s\n' "" "$asn" "$asname" "${net:--}" "${range:-unknown}"
 echo
 { csv "$line"; printf ','; csv "$range"; printf ','; csv "$org"; printf ','; csv "$net"; printf ','; csv "$emails"; printf ','; csv "$asn"; printf ','; csv "$asname"; printf ',%s,%s,' "$ptrn" "$ptrh"; csv "$ptre"; printf ',%s,' "$score"; csv "$verdict"; printf ','; csv "$reason"; echo; } >> "$OUTPUT"
done < "$INPUT"
echo "[+] Report written to: $OUTPUT"
