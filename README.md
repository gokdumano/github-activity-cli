# github-activity-cli

A small bash CLI that fetches a GitHub user's public event timeline,
caches it locally with ETag-based conditional requests, and prints a
grouped, icon-annotated activity feed straight to your terminal.

```bash
$ ./github-activity-cli.sh gokdumano

📦 gokdumano/github-activity-cli
----------------------
  🆕 Create        2026-06-30T13:04:40Z

📦 gokdumano/task-tracker-cli
----------------------
  📌 Push          2026-06-26T19:05:07Z
  📌 Push          2026-06-26T19:04:34Z
  📌 Push          2026-06-26T18:58:42Z
  📌 Push          2026-06-26T18:55:14Z
  📌 Push          2026-06-26T18:47:19Z
  📌 Push          2026-06-26T18:27:34Z
  📌 Push          2026-06-26T13:48:16Z
  📌 Push          2026-06-26T13:36:33Z
  📌 Push          2026-06-26T08:14:11Z
  🆕 Create        2026-06-26T08:13:49Z

📦 gokdumano/yahoo-finance-bash-cli
----------------------
  📌 Push          2026-06-17T22:59:47Z
  📌 Push          2026-06-17T22:54:29Z
  📌 Push          2026-06-17T22:54:20Z
  📌 Push          2026-06-17T22:47:14Z
  📌 Push          2026-06-17T22:33:13Z
  📌 Push          2026-06-17T22:31:58Z
  📌 Push          2026-06-17T18:14:59Z
  📌 Push          2026-06-17T18:10:17Z
  📌 Push          2026-06-17T18:08:10Z
  📌 Push          2026-06-17T18:02:52Z
  📌 Push          2026-06-17T18:02:29Z
  🆕 Create        2026-06-17T18:02:00Z

📦 ryogrid/create_pg_super_document
----------------------
  ⭐ Star           2026-06-23T09:34:52Z
```

## Requirements

- `bash` >= 4
- `curl` >= 7.95 (uses the `%output{}` write-out variable)
- `jq`

## Install

```bash
git clone https://github.com/<you>/github-activity-cli.git
cd github-activity-cli
chmod +x github-activity.sh
```

## Usage

```bash
./github-activity.sh <username> [per_page] [page]
```

| Argument   | Description                  | Default |
| ---------- | ----------------------------- | ------- |
| `username` | GitHub login (required)       | —       |
| `per_page` | Results per page (1–100)      | `30`    |
| `page`     | Starting page number          | `1`     |

```bash
# Default: 30 events per page, starting at page 1
./github-activity.sh gokdumano

# 50 events per page
./github-activity.sh gokdumano 50

# Start from page 2
./github-activity.sh gokdumano 30 2
```

The script automatically paginates through every available page and
merges the results before printing.

## Caching

Responses are cached under `~/.cache/github-activity-cli/<username>/`
using GitHub's `ETag` header. On repeat runs, only changed pages are
re-downloaded — unchanged pages return `304 Not Modified` and the
cached copy is reused, which keeps you well within GitHub's rate
limits.

To clear the cache for a user:

```bash
rm -rf ~/.cache/github-activity-cli/<username>
```

## Authentication

Unauthenticated requests are limited to **60/hour** by GitHub. If you
hit that limit, export a [personal access token](https://github.com/settings/tokens):

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
```

> **Note:** token support is not yet wired into the script — see
> `github-activity.sh` for the exact line to uncomment/add. Contributions
> welcome.
