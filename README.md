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
| [`.github/workflows/pr.yml`](.github/workflows/pr.yml) | Reusable workflow: pull-request opened / reopened / merged / closed embeds for `pull_request` events |

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

## Pull-request notifications

The `pr.yml` reusable workflow posts a branded embed when a PR is opened,
reopened, merged, or closed without merging — the same firehose Discord's
first-party GitHub app sends, but under the tonk name and icon (and your
`.github/discord.yml` personality) instead of "GitHub".

GitHub only runs a repo's own workflows in response to that repo's events, so
the trigger has to live in the caller — there's no way to fire it centrally
from `zandoh/tonk` without a hosted webhook service. But it needn't be a
second file: add a `pull_request` trigger and a `pr` job to the same
`tonk.yml` you already have. Each event runs only its matching job.

```yaml
# .github/workflows/tonk.yml
name: tonk
on:
  workflow_run:
    workflows: [CI, Release]
    types: [completed]
  pull_request:
    types: [opened, reopened, closed]
permissions:
  actions: read # recovery detection reads run history
  contents: read # reads .github/discord.yml
jobs:
  ci:
    if: github.event_name == 'workflow_run'
    uses: zandoh/tonk/.github/workflows/notify.yml@v2
    secrets:
      webhook: ${{ secrets.TONK_DISCORD_WEBHOOK }}
  pr:
    if: github.event_name == 'pull_request'
    uses: zandoh/tonk/.github/workflows/pr.yml@v2
    secrets:
      webhook: ${{ secrets.TONK_DISCORD_WEBHOOK }}
```

(Prefer them split? A standalone `tonk-pr.yml` with just the `pull_request`
trigger and the `pr` job works identically — it's a taste call, not a
requirement.)

Each event colors its embed distinctly — opened green, reopened blue, merged
purple, closed-without-merge grey. Draft PRs are skipped on open and reopen
(a draft isn't ready to announce); closing one still posts. Fork PRs receive
no secret, so their runs skip silently like everything else in tonk. Turn the
whole stream off without removing the workflow via
`notify.pull-request-activity: false` in `discord.yml`.

If you're migrating off the first-party GitHub app, run
`/github unsubscribe owner/repo` in the Discord channel once this is live so
the two don't double-post.

## Configuration

`.github/discord.yml` in the calling repo, read from the default branch.
Every key is optional.

| Key | Default | Meaning |
|---|---|---|
| `username` | `tonk` | Bot name shown on posts |
| `avatar` | the [tonk icon](https://zandoh.github.io/tonk/assets/tonk.png) | Bot avatar image URL |
| `notify.failure` | `true` | Post when a watched workflow fails (`notify.yml`) |
| `notify.recovery` | `true` | Post the first green after a failure (`notify.yml`) |
| `notify.pull-requests` | `false` | Include PR-triggered CI runs in failure/recovery (`notify.yml`) |
| `notify.pull-request-activity` | `true` | Post PR opened/reopened/merged/closed embeds (`pr.yml`) |

`pull-requests` and `pull-request-activity` are different knobs: the first
decides whether a *CI run* on a PR can trigger a failure/recovery ping; the
second decides whether the PR's *lifecycle* (open, merge, close) is announced
at all. For `pr.yml`, this file is read from the base ref, not the PR head.

```yaml
username: Hearth CI
avatar: https://example.com/hearth.png
notify:
  failure: true
  recovery: true
  pull-requests: false
  pull-request-activity: true
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
| `username` | no | `tonk` | Bot name for this post |
| `avatar-url` | no | the [tonk icon](https://zandoh.github.io/tonk/assets/tonk.png) | Bot avatar image URL for this post |
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
