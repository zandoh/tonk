# tonk

Shared Discord notifications for GitHub Actions: one composite action to send
an embed, one reusable workflow that turns raw workflow results into signals
worth reading — **failures** and **back to green** recoveries, exactly once
per incident.

Named for Mechagon's Tussle Tonks: a little machine that keeps fighting.

## What you get

- **`actions/discord-notify`** — a composite action that posts one embed.
  Guard rails built in: skips silently when the webhook is unset (fork PRs
  never fail), warns instead of failing when Discord is down, truncates to
  Discord's limits.
- **`.github/workflows/notify.yml`** — a reusable workflow for
  `workflow_run` events. Notifies on failure, and detects recovery by asking
  the GitHub API whether the previous completed run of the same workflow on
  the same branch was red — so you get one "back to green" per incident, not
  one per green push.

## Quick start

1. Create a Discord webhook (channel → Integrations → Webhooks) and store it:

   ```sh
   gh secret set TONK_DISCORD_WEBHOOK --repo you/your-repo
   ```

2. Add the thin caller, listing the workflows you want watched
   (`workflow_run` requires naming them — no wildcards):

   ```yaml
   # .github/workflows/tonk.yml
   name: tonk
   on:
     workflow_run:
       workflows: [CI, Release]
       types: [completed]
   permissions:
     actions: read # recovery detection reads run history
   jobs:
     notify:
       uses: zandoh/tonk/.github/workflows/notify.yml@v1
       secrets:
         webhook: ${{ secrets.TONK_DISCORD_WEBHOOK }}
   ```

3. Optionally add a personality file:

   ```yaml
   # .github/discord.yml — all keys optional, defaults shown
   username: "" # bot name for posts; empty keeps the webhook's default
   notify:
     failure: true
     recovery: true
     pull-requests: false # PR runs are skipped by default; red PRs are part of iterating
   ```

The config is read from the repo's default branch (where `workflow_run`
executes), so config changes take effect on merge.

## Sending a one-off embed

For notifications that aren't failure/recovery — release announcements,
digests, deploy summaries — call the action directly:

```yaml
- name: Announce release on Discord
  uses: zandoh/tonk/actions/discord-notify@v1
  with:
    webhook-url: ${{ secrets.TONK_DISCORD_WEBHOOK }}
    title: 🚀 my-tool v1.2.3 released
    description: ${{ steps.notes.outputs.body }}
    url: https://github.com/you/my-tool/releases/tag/v1.2.3
    color: "5793266"
```

### Action inputs

| Input | Required | Default | Notes |
|---|---|---|---|
| `webhook-url` | yes | — | Empty value skips silently (fork-safe) |
| `title` | yes | — | Truncated to 256 chars |
| `status` | no | — | `success` / `failure`; adds ✅/❌ prefix and sets the default color |
| `description` | no | `repo · branch · sha` + commit subject | Truncated to 4096 chars |
| `url` | no | current run URL | Link target for the title |
| `color` | no | from `status` | Decimal; failure `15548997`, success `5763719`, otherwise `3447003` |
| `username` | no | webhook default | Bot name for this post |
| `footer` | no | workflow name | |

## Conventions

- Colors: red `15548997` failure, green `5763719` recovery/success.
- Webhook URLs are secrets, never in workflow files. The canonical secret
  name is `TONK_DISCORD_WEBHOOK`.
- A notification must never break the thing it reports on: unset webhook →
  skip, Discord outage → `::warning::`, fork PR → skip.

## Verifying a setup

Set `TONK_DISCORD_WEBHOOK` on this repo and dispatch the **Test embed** workflow;
the embed landing in the channel proves the secret and the action end to end.

## Development

```sh
make tools   # one-time: install the toolchain (macOS/Homebrew)
make check   # everything CI runs: lint + test
```

`make lint` runs actionlint (workflow semantics), yamllint (style — this is
the formatting gate; there's no YAML auto-formatter on purpose, they mangle
comment-heavy workflow files), zizmor (workflow security), and shellcheck.

`make test` runs a bats suite against the bash embedded in the YAML — the
scripts are extracted from the real files at test time
(`scripts/extract-step.sh`), so tests can't drift from what ships. Network
edges (curl, gh) are shimmed; tests assert on the exact JSON payloads.

Dependabot keeps the SHA-pinned actions fresh (with a 7-day cooldown); a
bump only reaches consumers when a new tag is cut.

## Versioning

`v1` is a moving major tag; the reusable workflow and the composite action
are tagged together and reference each other at the same major. Pin `@v1`
(or a commit SHA if your repo hash-pins actions).

## Roadmap

This repo is Phase 1 of tonk: the shared layer, no new product. A `tonk`
binary (per-repo `tonk.yml` rules, digests, `init`/`send`/`sync`/`lint`) is
gated on living with this layer first.
