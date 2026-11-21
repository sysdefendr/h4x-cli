## h4x-cli v0.5.0

Modular helper CLI for authorized penetration testing.

### Modules

- `target-gen`: Generate line-delimited target lists or open-port inventories from Nmap normal output.
- `scope-check`: Collect passive WHOIS, netname, email-domain, ASN, and sampled PTR evidence. It intentionally produces no verdict, confidence score, or likelihood score.
- `comment-scraper`: Extract comments from web pages and same-origin application assets.
- `kerb-target-gen`: Convert Kerbrute `userenum` output into unique, line-delimited usernames with `@domain` removed.
- `masscan-to-csv`: Convert Masscan `-oL` output into a CSV constrained to an explicit scope file, with optional exclusions.

### Install

```bash
chmod +x install.sh
./install.sh
```

### Examples

```bash
h4x-cli scope-check -input-file cidrs.txt
h4x-cli scope-check -input-file cidrs.txt --ptr-sample 8 --output-file evidence.csv

h4x-cli kerb-target-gen -input-file kerbrute-output.txt
h4x-cli kerb-target-gen -input-file kerbrute-output.txt --output-file valid-users.txt

h4x-cli masscan-to-csv --scope scope.txt --input-file masscan-results.txt
h4x-cli masscan-to-csv --scope scope.txt --exclusions exclusions.txt --input-file masscan-results.txt --output-file results.csv

h4x-cli target-gen --list-ports -input-file scan.nmap
h4x-cli target-gen -p 445/tcp -input-file scan.nmap

h4x-cli comment-scraper -u https://app.example.com/ --crawl-assets --output-file
```

### Input notes

Scope and exclusion files accept one IPv4/IPv6 address or CIDR per line. Blank lines and lines beginning with `#` are ignored. `masscan-to-csv` includes every usable in-scope address not covered by the exclusions file, including addresses with zero open ports.
