# tonk

> Shared Discord notifications for GitHub Actions — failure alerts,
> once-per-incident "back to green" recoveries, and a reusable embed action
> with guard rails.

[![CI](https://github.com/zandoh/tonk/actions/workflows/ci.yml/badge.svg)](https://github.com/zandoh/tonk/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/tag/zandoh/tonk?label=release)](https://github.com/zandoh/tonk/tags)

**Docs site:** [zandoh.github.io/tonk](https://zandoh.github.io/tonk/)

Posting an embed to a webhook is the easy part. The hard part is state:
knowing that this red build is worth a ping, and that this green build is the
*first* green after a red streak — not the hundredth routine success. tonk
handles that by recomputing state from the GitHub API at notification time.
No server, no database, nothing to host.

## What's in the box

| Piece | Purpose |
|---|---|
| [`action.yml`](action.yml) (repo root) | Composite action that posts one embed, with guard rails built in |
| [`.github/workflows/notify.yml`](.github/workflows/notify.yml) | Reusable workflow: failure alerts + back-to-green recovery detection for `workflow_run` events |

## Quick start

1. Create a Discord webhook (channel → Integrations → Webhooks) and store it:

   ```sh
   gh secret set TONK_DISCORD_WEBHOOK --repo you/your-repo
   ```

2. Add a thin caller workflow, naming the workflows to watch
   (`workflow_run` requires explicit names — no wildcards):

   ```yaml
   # .github/workflows/tonk.yml
   name: tonk
   on:
     workflow_run:
       workflows: [CI, Release]
       types: [completed]
   permissions:
     actions: read # recovery detection reads run history
     contents: read # reads .github/discord.yml — required on private repos
   jobs:
     notify:
       uses: zandoh/tonk/.github/workflows/notify.yml@v2
       secrets:
         webhook: ${{ secrets.TONK_DISCORD_WEBHOOK }}
   ```

3. Optionally add `.github/discord.yml` to give the repo a personality
   (see [Configuration](#configuration)).

That's the whole integration. Failures in the watched workflows post a red
embed; the first green run after a failure posts a "back to green" — and
only the first, because the reusable workflow checks whether the previous
completed run of the same workflow on the same branch was red.

## Configuration

`.github/discord.yml` in the calling repo, read from the default branch.
Every key is optional.

| Key | Default | Meaning |
|---|---|---|
| `username` | webhook default | Bot name shown on posts |
| `notify.failure` | `true` | Post when a watched workflow fails |
| `notify.recovery` | `true` | Post the first green after a failure |
| `notify.pull-requests` | `false` | Include PR-triggered runs (red PRs are part of iterating, so they're excluded by default) |

```yaml
username: Hearth CI
notify:
  failure: true
  recovery: true
  pull-requests: false
```

## One-off embeds

For notifications that aren't failure/recovery — release announcements,
digests, deploy summaries — call the action directly from any step:

```yaml
- name: Announce release on Discord
  uses: zandoh/tonk@v2
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

## Guarantees

A notification must never break the thing it reports on:

- **Unset webhook → silent skip.** Fork PRs don't receive secrets; their
  builds must not fail because of a missing notification credential.
- **Discord outage → warning, not failure.** Delivery errors emit a
  `::warning::` annotation and exit 0.
- **Untrusted text can't inject.** Titles, commit messages, and bodies flow
  through env vars into `jq` — never through shell interpolation.

## Versioning

`v2` is a moving major tag; the reusable workflow and the composite action
are tagged together and reference each other at the same major. Pin `@v2`,
or a commit SHA if your repo hash-pins actions. (`v1` tags still resolve to
the old layout, where the action lived at `actions/discord-notify`.)

## Development

```sh
make tools   # one-time: install the toolchain (macOS/Homebrew)
make check   # everything CI runs: lint + test
```

`make lint` runs actionlint, yamllint (the formatting gate — there is
deliberately no YAML auto-formatter; they mangle comment-heavy workflow
files), zizmor, and shellcheck. `make test` runs a bats suite against the
bash embedded in the YAML: scripts are extracted from the real files at test
time (`scripts/extract-step.sh`) so tests can't drift from what ships, and
network edges (curl, gh) are shimmed so assertions run against exact JSON
payloads.

To verify a live setup end to end, set `TONK_DISCORD_WEBHOOK` on this repo
and dispatch the **Test embed** workflow.

## License

[MIT](LICENSE). Named for the Tussle Tonks of Mechagon — a little machine
that keeps fighting.
