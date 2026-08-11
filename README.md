# otp.com API contract

The **OpenAPI 3.1 spec** for the public otp.com OTP API: [`openapi.yaml`](./openapi.yaml).

This file is the single source of truth for the API surface. Every language SDK and the MCP server
are generated or kept in sync from it, so a change lands here first and reaches clients second.

| | Package | Repo |
| --- | --- | --- |
| Node.js / TypeScript | `@otp.com/sdk-node` | [otp-com/sdk-node](https://github.com/otp-com/sdk-node) |
| PHP | `otp-com/sdk-php` | [otp-com/sdk-php](https://github.com/otp-com/sdk-php) |
| Go | `github.com/otp-com/sdk-go` | [otp-com/sdk-go](https://github.com/otp-com/sdk-go) |
| Python | `otp-sdk` | [otp-com/sdk-python](https://github.com/otp-com/sdk-python) |
| MCP server | `@otp.com/mcp` | [otp-com/mcp](https://github.com/otp-com/mcp) |

## The API in one screen

Authenticate every request with your API key as a Bearer token (`otp_live_…` for production,
`otp_test_…` for sandbox). Base URL: `https://api.otp.com/api/v1`.

| Endpoint | Does |
| --- | --- |
| `POST /otp/send` | Generate and deliver a code. You pass the recipient; account routing picks the channel. Returns `otp_id`. |
| `POST /otp/verify` | Check the code the user entered. `matched: true` means correct. |
| `POST /otp/resend` | Resend a pending OTP, advancing to the next channel (or one you name). |
| `GET /otp/{otp_id}` | Current status: `pending`, `approved`, `failed`, or `expired`. |

The code itself is never returned by the API. Errors are always
`{"error": {"type", "message", "details"?}}`.

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

## Editing the spec

Keep `openapi.yaml` a mirror of the live API: if the backend changed, this file changes in the same
breath. Validate before pushing:

```sh
npx @redocly/cli lint openapi.yaml
```

A change here is a change to every SDK. Removing or renaming a field is a breaking change for four
published packages, so treat additive edits as routine and everything else as a release decision.

## Regenerating the SDKs

Fan-out is **manual**. Pushing a spec change does not touch the SDKs; you decide when they follow.

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

- [`notify-sdks.yml`](./.github/workflows/notify-sdks.yml) fires a `spec-updated`
  `repository_dispatch` at each SDK repo.
- Each SDK repo listens for that event (and also has a manual **Update from spec** run), fetches
  this `openapi.yaml`, regenerates its client, and opens a PR if anything changed.
- Nothing is force-pushed: a human reviews and merges each regeneration PR, then tags a release.

## License

MIT
