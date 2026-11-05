# h4x-cli v0.4.1

Modular helper CLI for penetration testing.

## Modules

| Module | Description |
|---|---|
| [`comment-scraper`](#comment-scraper) | Extract comments from web pages and common web application files |
| [`target-gen`](#target-gen) | Generate line-delimited lists of targets from nmap output |
| [`scope-check`](#scope-check) | Scope checker that passively checks domain ownership from CIDR ranges (external) |

---

## comment-scraper

### Usage

```text
h4x-cli comment-scraper -u <url> [options]
h4x-cli comment-scraper -input-file <urls.txt> [options]
```

### Input

```text
-u, --url <url>             URL to inspect (repeatable)
-i, -input-file, --input-file <file>
                            Line-delimited URLs; blank lines and # comments are ignored
```

### Options

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

## target-gen

### Usage

```text
h4x-cli target-gen -p <port>[/protocol] -input-file <scan.nmap> [--output-file <file>]
h4x-cli target-gen --list-ports -input-file <scan.nmap> [--output-file <file>]
```

### Modes

```text
-p, --port <port>           Generate a line-delimited target list for an open port
-l, --list-ports            Display a table of the unique open ports found in the Nmap file
                            and how many hosts have each port open
```

### Input and output

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

## scope-check

### Usage

```text
h4x-cli scope-check -c "<client name>" -input-file <cidrs.txt> [options]
```

### Required

```text
-c, --client <name>          Client legal/common name
-i, -input-file, --input-file <file>
```

### Optional

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
> Likelihood is a score from 0-100 estimating whether the public range is registered to or controlled by the named client.
