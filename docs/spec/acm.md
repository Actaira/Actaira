# Agent Capability Manifest (ACM), draft v0

**Status: draft.** Version 0 of an open format for the capability contract of an AI agent: what the agent must be able to do, declared once in its repository and used in pull requests, for credentials, at runtime and before third parties. It is published by the Actaira project (Apache-2.0) and changes without notice while it is version 0. The JSON Schema is `schemas/acm.v0.json`; `actaira intent validate` checks a manifest against it and against the rules below that a schema cannot express.

## 1. Terms

- **Capability:** an action on a resource, written `<resource>.<action>`, for example `customer.read` or `money.refund`. Both parts are lowercase ASCII letters, digits and `_`, starting with a letter. The vocabulary of resources and actions comes from a knowledge base (for Actaira, `actaira-kb`); version 0 only fixes the form.
- **Agent:** identified by the stable `id` that the lockfile gives it (Actaira: a hash of framework, relative file and name).
- **Potential capability:** what a knowledge base says a tool could do. Not what a credential allows (effective) nor what was seen at runtime (observed).

## 2. Document

```json
{
  "acm_version": 0,
  "contracts": [
    {
      "agent": "<agent id>",
      "status": "accepted",
      "accepted_by": "<who accepted it>",
      "accepted_at": "2026-10-02",
      "owner": "<who answers for it>",
      "expires": "2027-04-01",
      "allow": ["customer.read", "money.refund"],
      "deny": ["customer.delete"],
      "limits": [
        {"capability": "money.refund", "per_operation": {"amount": 50000, "currency": "EUR"}},
        {"capability": "money.refund", "per_period": {"period": "month", "amount": 200000, "currency": "EUR", "count": 100}}
      ],
      "egress": ["api.stripe.com", "*.zendesk.com"]
    }
  ]
}
```

## 3. Rules

1. `allow` is the complete list of what the agent may do. A potential capability outside `allow` breaks the contract.
2. `deny` forbids explicitly and wins over `allow`. A capability in both lists is invalid.
3. No wildcards in capabilities in version 0.
4. Amounts are integers in the minor unit of their currency (ISO 4217): 50000 with `EUR` is 500 euros. A decimal is invalid.
5. `period` is one of `day`, `week` or `month`, in UTC.
6. A limit only bounds what it names. Where a capability has no limit, the maximum exposure is "no limit", never a number.
7. `egress` lists host names; `*.` matches one or more labels before the rest. No scheme, path or port.
8. `status` is `draft` or `accepted`. A draft (for example, proposed by a tool from the current code) carries `"confidence": "inferred"` and binds nothing until a person accepts it, setting `accepted_by` and `accepted_at`.
9. After `expires`, the contract is shown as expired and binds nothing; tools must show that, not drop it silently.
10. An agent with no contract is "no contract", not an error.
11. Text is UTF-8 in Unicode NFC.

## 4. How Actaira uses it

- The manifest lives in `actaira.intent.json` at the root of the repository, with whitespace, so a pull request shows each change.
- `actaira lock` validates it and copies its canonical form into the `intent` block of `actaira.lock`; the block is never the source (ADR 0004).
- An invalid manifest is an input error: `actaira lock` exits with 2 and `actaira intent validate` with 1, both with the reason.
- A contract whose agent is not in the lockfile (its file moved or was renamed) is invalid, with the agent `id` in the message.
- `actaira.lock` schema version 1 accepts `acm_version` 0. Accepting another version is a change of the lockfile schema.

## 5. Open questions for version 1

- Wildcards and resource scoping (a customer, an account).
- Contracts per customer of an agent operator, narrowing the repository one.
- Signing: in version 0 the signature is the recorded acceptance, protected by the review of the pull request.
