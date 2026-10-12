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
| `POST /otp/send` | Generate and deliver a code. You pass the recipient (and the end user's IP as `client_ip`; requests without it share a much tighter rate limit); account routing picks the channel. Returns `otp_id`. |
| `POST /otp/verify` | Check the code the user entered. `matched: true` means correct. |
| `POST /otp/resend` | Resend a pending OTP, advancing to the next channel (or one you name). |
| `GET /otp/{otp_id}` | Current status: `pending`, `approved`, `failed`, or `expired`. |
| `POST /verifications/exchange` | Exchange the `verification_token` a mobile SDK received for the recipient that was actually verified. |

The code itself is never returned by the API. Errors are always
`{"error": {"type", "message", "details"?}}`.

## WhatsApp: how the OTP completes

Every send, resend and status response carries `completion`, which tells you how this OTP finishes.
SMS, email and Telegram always complete with `code`. Which WhatsApp mode applies is configured per
account:

| `completion` | `action_url` | What happens |
| --- | --- | --- |
| `code` | `null` | The code was delivered (any channel, or WhatsApp in template mode). The user enters it; you call `/otp/verify`. |
| `code` | set | WhatsApp code-back. The user opens the `wa.me` link and sends us the prefilled message; we reply with the code. Then `/otp/verify` as on SMS. |
| `inbound` | set | WhatsApp inbound approval. The prefilled message itself approves the OTP; there is no code. Poll `GET /otp/{otp_id}` every 3 to 5 seconds until `status` leaves `pending`, or take the `otp.approved` webhook. |

Calling `/otp/verify` on an `inbound` OTP never matches while it is pending and spends an attempt;
once approved it simply reports the approved OTP. Sandbox OTPs always complete with `code`; on
WhatsApp they still return a sample `action_url`. If the user has no WhatsApp, `/otp/resend` moves
the OTP onto the next configured channel: leaving WhatsApp for a code channel sets `completion`
back to `code`.

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
