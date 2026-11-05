# h4x-cli v0.4.1

Modular helper CLI for authorized penetration testing.

## Modules

```text
target-gen        Generate line-delimited lists of targets from nmap output
scope-check       Scope checker that passively checks domain ownership from CIDR ranges (external)
comment-scraper   Extract comments from web pages and common web application files
```

## target-gen port inventory

```bash
h4x-cli target-gen --list-ports -input-file scan.nmap
h4x-cli target-gen --list-ports -input-file scan.nmap --output-file open-ports.txt
```

The inventory mode prints unique entries such as `80/tcp`, `443/tcp`, and `161/udp` whose state is exactly `open`. It does not create a file unless `--output-file` is supplied.

## comment-scraper

```bash
h4x-cli comment-scraper -u https://app.example.com/ --crawl-assets
h4x-cli comment-scraper -u https://app.example.com/ --crawl-assets --output-file
h4x-cli comment-scraper -u https://app.example.com/ --output-file findings.txt
```

No file is created by default. Supplying `--output-file` without a name creates `<fqdn>-comments-<random5>.txt`. Review flags identify comments containing URLs, credential-related terms, version strings or dates, and common web server technology names.
