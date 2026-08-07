# otp API contract (source of truth)

This repo holds the **OpenAPI 3.1 spec** for the public otp OTP API: [`openapi.yaml`](./openapi.yaml).

It is the single source of truth for the API surface. The language SDKs
([sdk-node](https://github.com/otp-com/sdk-node), [sdk-php](https://github.com/otp-com/sdk-php),
[sdk-go](https://github.com/otp-com/sdk-go), [sdk-python](https://github.com/otp-com/sdk-python))
and the [MCP server](https://github.com/otp-com/mcp) are generated / kept in sync from this file.

## How the automation works

```
             edit openapi.yaml
                    │
     run notify-sdks.yml by hand (this repo)
                    │
        notify-sdks.yml  ──repository_dispatch("spec-updated")──►  sdk-node
                    │                                              sdk-php
                    │                                              sdk-go
                    └──────────────────────────────────────────►  sdk-python
                    ▼
   each SDK repo regenerates from the new spec and opens a PR
```

- **Fan-out is manual.** Pushing a spec change does *not* touch the SDKs; you run
  [`notify-sdks.yml`](./.github/workflows/notify-sdks.yml) when you want them to follow. It fires a
  `spec-updated` `repository_dispatch` at each SDK repo.
- **Each SDK repo** listens for that event (and also has a manual **Update from spec** run), fetches
  this `openapi.yaml`, regenerates its client, and opens a PR if anything changed.
- Nothing is force-pushed: a human reviews and merges each SDK's regeneration PR, then tags a release.

## Regenerating locally

[`update-sdk.sh`](./update-sdk.sh) does the same job on your machine, against the sibling `sdk-*`
checkouts, using the same generator image and flags as each repo's `generate.yml`. It always reads
your **working copy** of `openapi.yaml` (never the pushed one), so you can regenerate the SDKs the
moment you drop a fresh spec in here and see the diff before anything is pushed.

```sh
./update-sdk.sh                     # all SDKs, generate only, no git writes
./update-sdk.sh sdk-node sdk-go     # only these repos
./update-sdk.sh --commit            # also branch + commit in each repo
./update-sdk.sh --pr                # also push and open the PR (what CI does)
```

Needs Docker (and `gh` for `--pr`). It expects `sdk-node`, `sdk-php`, `sdk-go` and `sdk-python` next
to this repo; set `SDK_ROOT` if they live elsewhere. `--commit` and `--pr` refuse to touch a repo
with a dirty working tree.

## WhatsApp: the code comes back to the user

Verification is identical on every channel (the user enters a code, you call `/otp/verify`); only
delivery differs. When routing picks WhatsApp, `/otp/send` (and `/otp/resend`) returns an
`action_url` and the code is **not** sent yet:

1. Send the OTP. If `channel` is `whatsapp`, the response carries `action_url` (a `wa.me` link).
2. Open `action_url` for the user. They send us the prefilled message from their own WhatsApp.
3. We reply over WhatsApp with the code. The OTP stays `pending` until the user enters it.
4. Call `/otp/verify` with the entered code, exactly as on SMS, email, or Telegram.

`action_url` is `null` on every other channel. If the user has no WhatsApp, `/otp/resend` moves the
OTP onto the next configured channel.

## Setup

Add an org secret `SDK_DISPATCH_TOKEN` (a fine-grained PAT or GitHub App token with `contents:write`
+ `actions:write` on the `sdk-*` repos) so this repo can dispatch to them.

## Editing the spec

Keep `openapi.yaml` the mirror of the live API. Validate before pushing:

```sh
npx @redocly/cli lint openapi.yaml
```
