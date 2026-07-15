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
          push to main (this repo)
                    │
        notify-sdks.yml  ──repository_dispatch("spec-updated")──►  sdk-node
                    │                                              sdk-php
                    │                                              sdk-go
                    └──────────────────────────────────────────►  sdk-python
                    ▼
   each SDK repo regenerates from the new spec and opens a PR
```

- **Push a spec change** → [`notify-sdks.yml`](./.github/workflows/notify-sdks.yml) fires a
  `spec-updated` `repository_dispatch` at each SDK repo.
- **Each SDK repo** listens for that event (and also has a manual **Update from spec** run), fetches
  this `openapi.yaml`, regenerates its client, and opens a PR if anything changed.
- Nothing is force-pushed: a human reviews and merges each SDK's regeneration PR, then tags a release.

## Setup

Add an org secret `SDK_DISPATCH_TOKEN` (a fine-grained PAT or GitHub App token with `contents:write`
+ `actions:write` on the `sdk-*` repos) so this repo can dispatch to them.

## Editing the spec

Keep `openapi.yaml` the mirror of the live API. Validate before pushing:

```sh
npx @redocly/cli lint openapi.yaml
```
