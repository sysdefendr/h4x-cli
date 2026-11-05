#!/usr/bin/env bash
set -euo pipefail
usage() {
cat <<'USAGE'
Usage:
  h4x-cli comment-scraper -u <url> [options]
  h4x-cli comment-scraper -input-file <urls.txt> [options]

Input:
  -u, --url <url>             URL to inspect (repeatable)
  -i, -input-file, --input-file <file>
                              Line-delimited URLs; blank lines and # comments are ignored

Options:
  --crawl-assets              Inspect same-origin linked web application files
  -o, --output-file [file]    Save results. If no filename is supplied, use:
                              <fqdn>-comments-<random5>.txt
  --timeout <seconds>         Request timeout (default: 15)
  --user-agent <value>        Custom HTTP User-Agent
  --header <header>           Additional request header (repeatable)
  --max-assets <n>            Maximum linked assets per starting page (default: 100)
  --insecure                  Disable TLS certificate verification
  --include-empty             Print source headings that contain no comments
  --no-color                  Disable colored stdout
  -h, --help                  Show this help

Nothing is written to disk unless --output-file is used. Only explicitly supplied
URLs and, with --crawl-assets, same-origin linked files are requested.
USAGE
}
URLS=(); INPUT=""; OUTPUT=""; WRITE_OUTPUT=0; AUTO_OUTPUT=0; CRAWL=0; TIMEOUT=15
UA="h4x-cli-comment-scraper/0.4.1"; MAX_ASSETS=100; INSECURE=0; INCLUDE_EMPTY=0; COLOR=1; HEADERS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--url) URLS+=("${2:-}"); shift 2 ;;
    -i|-input-file|--input-file) INPUT="${2:-}"; shift 2 ;;
    -o|--output-file|-output-file)
      WRITE_OUTPUT=1
      if [[ $# -ge 2 && "${2:-}" != -* ]]; then OUTPUT="$2"; shift 2; else AUTO_OUTPUT=1; shift; fi ;;
    --crawl-assets) CRAWL=1; shift ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --user-agent) UA="${2:-}"; shift 2 ;;
    --header) HEADERS+=("${2:-}"); shift 2 ;;
    --max-assets) MAX_ASSETS="${2:-}"; shift 2 ;;
    --insecure) INSECURE=1; shift ;;
    --include-empty) INCLUDE_EMPTY=1; shift ;;
    --no-color) COLOR=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[!] Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done
for dep in curl python3; do command -v "$dep" >/dev/null || { echo "[!] Missing dependency: $dep" >&2; exit 1; }; done
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] && (( TIMEOUT > 0 )) || { echo "[!] --timeout must be a positive integer" >&2; exit 1; }
[[ "$MAX_ASSETS" =~ ^[0-9]+$ ]] || { echo "[!] --max-assets must be a non-negative integer" >&2; exit 1; }
if [[ -n "$INPUT" ]]; then
  [[ -f "$INPUT" ]] || { echo "[!] Input file not found: $INPUT" >&2; exit 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"; line="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<< "$line")"
    [[ -n "$line" ]] && URLS+=("$line")
  done < "$INPUT"
fi
(( ${#URLS[@]} > 0 )) || { echo "[!] Supply --url or --input-file" >&2; exit 1; }
if (( WRITE_OUTPUT )) && [[ -z "$OUTPUT" ]]; then
  HOST="$(python3 - "${URLS[0]}" <<'PY'
import sys,urllib.parse,re
h=urllib.parse.urlsplit(sys.argv[1]).hostname or 'comments'
print(re.sub(r'[^A-Za-z0-9._-]+','-',h))
PY
)"
  while :; do RAND=$(( (RANDOM * 32768 + RANDOM) % 90000 + 10000 )); OUTPUT="${HOST}-comments-${RAND}.txt"; [[ ! -e "$OUTPUT" ]] && break; done
fi
if (( COLOR )) && [[ -t 1 ]]; then PURPLE=$'\e[35m'; RED=$'\e[1;31m'; YELLOW=$'\e[1;33m'; WHITE=$'\e[37m'; CYAN=$'\e[36m'; RESET=$'\e[0m'; else PURPLE=""; RED=""; YELLOW=""; WHITE=""; CYAN=""; RESET=""; fi
TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
(( WRITE_OUTPUT )) && : > "$OUTPUT"
CURL=(curl -fsSL --max-time "$TIMEOUT" --user-agent "$UA"); (( INSECURE )) && CURL+=(-k)
for h in "${HEADERS[@]+"${HEADERS[@]}"}"; do CURL+=(-H "$h"); done
emit() { printf '%b' "$1"; (( WRITE_OUTPUT )) && printf '%b' "$2" >> "$OUTPUT"; return 0; }
declare -A SEEN
QUEUE=(); for u in "${URLS[@]}"; do QUEUE+=("$u|0"); done
TOTAL=0; SOURCES=0; FAILURES=0
while (( ${#QUEUE[@]} )); do
  ITEM="${QUEUE[0]}"; QUEUE=("${QUEUE[@]:1}"); IFS='|' read -r URL DEPTH <<< "$ITEM"
  [[ "$URL" =~ ^https?:// ]] || { echo "[!] Skipping unsupported URL: $URL" >&2; continue; }
  [[ -z "${SEEN[$URL]:-}" ]] || continue; SEEN[$URL]=1
  BODY="$TMPDIR/body.$RANDOM"; HDR="$TMPDIR/header.$RANDOM"
  if ! "${CURL[@]}" -D "$HDR" -o "$BODY" "$URL"; then echo "[!] Request failed: $URL" >&2; ((FAILURES++)) || true; continue; fi
  CTYPE="$(awk 'BEGIN{IGNORECASE=1}/^content-type:/{v=$0}END{sub(/^[^:]*:[[:space:]]*/,"",v);sub(/\r$/, "",v);print v}' "$HDR")"
  EXTRACTED="$TMPDIR/extracted.$RANDOM"
  python3 - "$BODY" > "$EXTRACTED" <<'PY'
import base64,pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_bytes().decode('utf-8','replace')
patterns=[r'<!--[\s\S]*?-->',r'<%--[\s\S]*?--%>',r'<%\s*\'[\s\S]*?%>',r'/\*[\s\S]*?\*/',r'(?m)(?<!:)//[^\r\n]*',r'(?m)^[ \t]*\#(?!\!)[^\r\n]*',r'(?m)^[ \t]*--(?!>)[^\r\n]*',r'(?m)^[ \t]*;[^\r\n]*']
url_re=re.compile(r"(?i)\b(?:https?|ftp)://[^\s<>\"']+")
secret_re=re.compile(r'(?i)\b(password|passwd|pass|secret|credential(?:s)?|api[_ -]?key|access[_ -]?key|private[_ -]?key|token)\b')
version_re=re.compile(r'(?i)\b(?:v(?:ersion)?\s*)?\d+\.\d+(?:\.\d+){0,2}(?:[-+][a-z0-9._-]+)?\b')
server_re=re.compile(r'(?i)\b(nginx|apache(?: httpd)?|iis|internet information services|tomcat|jetty|lighttpd|caddy|openresty|weblogic|websphere|jboss|wildfly|gunicorn|uwsgi)\b')
seen=set(); found=[]
for pat in patterns:
 for m in re.finditer(pat,text):
  c=m.group(0).strip()
  if not c or c in seen: continue
  seen.add(c); flags=[]
  if url_re.search(c): flags.append('URL')
  if secret_re.search(c): flags.append('SECRET/CREDENTIAL')
  if version_re.search(c): flags.append('VERSION OR DATE')
  if server_re.search(c): flags.append('WEB SERVER')
  found.append((m.start(),text.count('\n',0,m.start())+1,','.join(flags),c))
for _,line,flags,c in sorted(found):
 print(f'{line}|{flags}|{base64.b64encode(c.encode()).decode()}')
PY
  COUNT="$(wc -l < "$EXTRACTED" | tr -d ' ')"
  if (( COUNT > 0 || INCLUDE_EMPTY )); then
    emit "${CYAN}===== ${URL} =====${RESET}\nContent-Type: ${CTYPE:-unknown}\nComments: ${COUNT}\n\n" "===== ${URL} =====\nContent-Type: ${CTYPE:-unknown}\nComments: ${COUNT}\n\n"
    while IFS='|' read -r LINE FLAGS ENCODED || [[ -n "$LINE$FLAGS$ENCODED" ]]; do
      [[ -n "$LINE" ]] || continue
      COMMENT="$(python3 - "$ENCODED" <<'PY'
import base64,sys
print(base64.b64decode(sys.argv[1]).decode('utf-8','replace'))
PY
)"
      if [[ -n "$FLAGS" ]]; then
        emit "${RED}[REVIEW: ${FLAGS//,/ | }]${RESET}\n" "[REVIEW: ${FLAGS//,/ | }]\n"
      fi
      emit "${PURPLE}[line ${LINE}]${RESET}\n${WHITE}${COMMENT}${RESET}\n\n" "[line ${LINE}]\n${COMMENT}\n\n"
    done < "$EXTRACTED"
    emit "\n" "\n"; ((SOURCES++)) || true; TOTAL=$((TOTAL+COUNT))
  fi
  if (( CRAWL && DEPTH == 0 && MAX_ASSETS > 0 )); then
    ASSETS="$TMPDIR/assets.$RANDOM"
    python3 - "$URL" "$BODY" "$MAX_ASSETS" > "$ASSETS" <<'PY'
import pathlib,re,sys,urllib.parse
base,path,limit=sys.argv[1],sys.argv[2],int(sys.argv[3]); text=pathlib.Path(path).read_bytes().decode('utf-8','replace')
r=urllib.parse.urlsplit(base); origin=(r.scheme.lower(),r.netloc.lower()); seen=set()
exts=('.js','.mjs','.cjs','.ts','.tsx','.jsx','.css','.html','.htm','.jsp','.jspx','.php','.asp','.aspx','.xml','.json','.map','.vue','.svelte','.txt','.svg','.manifest')
for m in re.finditer(r'''(?is)(?:src|href|data-src)\s*=\s*["']([^"'#]+)["']''',text):
 u=urllib.parse.urljoin(base,m.group(1).strip()); p=urllib.parse.urlsplit(u)
 if p.scheme not in ('http','https') or (p.scheme.lower(),p.netloc.lower())!=origin: continue
 if not (p.path.lower().endswith(exts) or any(x in u.lower() for x in ('script','stylesheet','manifest'))): continue
 u=urllib.parse.urlunsplit((p.scheme,p.netloc,p.path,p.query,''))
 if u in seen: continue
 seen.add(u); print(u)
 if len(seen)>=limit: break
PY
    while IFS= read -r A; do [[ -n "$A" ]] && QUEUE+=("$A|1"); done < "$ASSETS"
  fi
done
printf '[+] Sources with comments: %s\n[+] Comments extracted: %s\n' "$SOURCES" "$TOTAL"
(( WRITE_OUTPUT )) && echo "[+] Results written to: $OUTPUT" || echo "[*] No output file requested; results were printed to stdout only."
(( FAILURES == 0 )) || echo "[~] Requests that failed: $FAILURES"
(( TOTAL > 0 )) || exit 2
