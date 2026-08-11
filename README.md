# otp.com API contract

The **OpenAPI 3.0.0 spec** for the public otp.com OTP API: [`openapi.yaml`](./openapi.yaml).

This file is the contract every language SDK and the MCP server are generated from. It is **generated
output**, not hand-written: the API server emits it from its own controllers, and it is copied here.
Editing it by hand is how the two drift apart, which is exactly what this arrangement replaced.

| | Package | Repo |
| --- | --- | --- |
| Node.js / TypeScript | `@otp.com/sdk-node` | [otp-com/sdk-node](https://github.com/otp-com/sdk-node) |
| PHP | `otp-com/sdk-php` | [otp-com/sdk-php](https://github.com/otp-com/sdk-php) |
| Go | `github.com/otp-com/sdk-go` | [otp-com/sdk-go](https://github.com/otp-com/sdk-go) |
| Python | `otp-sdk` | [otp-com/sdk-python](https://github.com/otp-com/sdk-python) |
| MCP server | `@otp.com/mcp` | [otp-com/mcp](https://github.com/otp-com/mcp) |

## The API in one screen

Authenticate every request with your API key as a Bearer token (`otp_live_…` for production,
`otp_test_…` for sandbox). Base URL: `https://api.otp.com/api/v1`. In the spec that splits into the
server (`https://api.otp.com`) and the `/api/v1` prefix on every path, which is what the generated
SDKs take as their configuration; the URL on the wire is the same.

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

## Updating the spec

`openapi.yaml` is not edited here. It comes from the API server (the private `otp-backend` repo),
which generates it from the NestJS controllers and DTOs:

```sh
./otp openapi                       # in otp-backend: rewrites docs/contract/openapi.yaml
cp ../otp-backend/docs/contract/openapi.yaml openapi.yaml
npx @redocly/cli lint openapi.yaml  # optional; the generator image also has `validate`
```

So a wording change, a new field or a new error status is a change to a decorator over there, never a
hand edit here. Schema names and `operationId`s are the SDK's public surface: renaming one is a
breaking change for four published packages, so treat additive changes as routine and everything else
as a release decision.

## Regenerating the SDKs

Fan-out is **manual**. Pushing a spec change does not touch the SDKs; you decide when they follow.

```
         copy in a fresh openapi.yaml
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
