# h4x-cli v0.4.1

Modular helper CLI for penetration testing.

## Installation
```text
./install.sh
```

## Modules

| Module | Description |
|---|---|
| [`comment-scraper`](#comment-scraper) | Extract comments from web pages and common web application files |
| [`target-gen`](#target-gen) | Generate line-delimited lists of targets from nmap output |
| [`scope-check`](#scope-check) | Scope checker that passively checks domain ownership from CIDR ranges (external) |

---

## Comment Scraper
#### Enter a URL and Comment Scraper will extract all detected source code comments for human review. Detects comments from HTML files, JS files, CSS, PHP comments and more. Save to a file or just read in stdout. Use ```--crawl-assets``` to extract comments of same-origin linked app endpoints.

### Usage

```text
h4x-cli comment-scraper -u <url> [options]
h4x-cli comment-scraper -input-file <urls.txt> [options]
```

### Comment Scraper Input

```text
-u, --url <url>             URL to inspect (repeatable)
-i, -input-file, --input-file <file>
                            Line-delimited URLs; blank lines and # comments are ignored
```

### Comment Scraper Options

```text
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
```

> [!NOTE]
> Nothing is written to disk unless `--output-file` is used. Only explicitly supplied URLs and, with `--crawl-assets`, same-origin linked files are requested.

---

## Target File Generator
#### Generate line-delimited target files provided with .nmap file input. The ```-l or --list-ports``` option will display all unique ports and amounts of each unique open port as well. Then choose which port and all affected hosts will be extracted and added to the target list.

### Usage

```text
h4x-cli target-gen -p <port>[/protocol] -input-file <scan.nmap> [--output-file <file>]
h4x-cli target-gen --list-ports -input-file <scan.nmap> [--output-file <file>]
```

### Target File Generator Modes

```text
-p, --port <port>           Generate a line-delimited target list for an open port
-l, --list-ports            Display a table of the unique open ports found in the Nmap file
                            and how many hosts have each port open
```

### Target File Generator Input and output

```text
-i, -input-file, --input-file <file>
                            Nmap normal-output (.nmap) file
-o, --output-file <file>    Custom output file
                            Target generation uses an automatic filename when omitted.
                            Port listing writes no file unless this option is supplied.
--no-color                  Disable colored output
-h, --help                  Show this help
```

> [!NOTE]
> Only entries whose state is exactly `open` are included. `closed`, `filtered`, `open|filtered`, and `closed|filtered` entries are ignored.

---

## Scope Check
#### Leverages ```dig``` and ```whois``` to passively** determine the likelihood* that a CIDR range belongs to the intended target.

### Usage

```text
h4x-cli scope-check -c "<client name>" -input-file <cidrs.txt> [options]
```

### Scope Check Required Options

```text
-c, --client <name>          Client legal/common name
-i, -input-file, --input-file <file>
```

### Scope Check Options

```text
-a, --alias <name>           Additional client name, brand, or subsidiary (repeatable)
-d, --domain <domain>        Client-owned domain (repeatable)
-o, --output-file <file>     CSV report path
--ptr-sample <n>             PTR lookups per range (default: 8; 0 disables)
--delay <seconds>            Delay between WHOIS queries (default: 1)
--max-segments <n>           Retained for command compatibility (default: 64)
--no-color                   Disable colored output
-h, --help                   Show this help
```

> [!NOTE]
> *Likelihood is a score from 0-100 estimating whether the public range is registered to or controlled by the named client.
>
> **If a reverse-DNS lookup isn't already cached, your resolver asks whoever holds the reverse-DNS records for that IP range. That's usually the ISP or hosting provider, but some organizations run that themselves. So the query might reach a DNS server the client (or a third party) operates.
>
>Even then, it's a normal public DNS lookup, the same kind that happens whenever anyone resolves a hostname. It doesn't probe, scan or connect to any host in the range, and it's generally treated as passive recon or OSINT.
>
>If you want a stricter guarantee, turn off reverse DNS:
>
>```h4x-cli scope-check -c "Example Corp, LLC" -input-file cidrs.txt --ptr-sample 0```
>
>Then the only queries go to the registries and Team Cymru, and nothing can reach client- or target-operated infrastructure. The trade-off is that the likelihood score loses the points it would get from reverse-DNS names that match the client's domain, so expect slightly lower scores for ranges that really are the client's.
