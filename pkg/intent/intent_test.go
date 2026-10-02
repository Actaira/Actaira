package intent

import (
	"strings"
	"testing"
)

const agentA = "0123456789abcdef"
const agentB = "fedcba9876543210"

// accepted is a valid manifest with one accepted contract for agentA.
const accepted = `{
  "acm_version": 0,
  "contracts": [
    {
      "agent": "0123456789abcdef",
      "status": "accepted",
      "accepted_by": "@ana",
      "accepted_at": "2026-10-01",
      "owner": "@ana",
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
}`

func parse(t *testing.T, src string) Manifest {
	t.Helper()
	m, err := Parse([]byte(src))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	return m
}

// parseFails checks that Parse rejects src and that the error says each of want.
func parseFails(t *testing.T, src string, want ...string) {
	t.Helper()
	_, err := Parse([]byte(src))
	if err == nil {
		t.Fatalf("Parse accepted:\n%s", src)
	}
	for _, w := range want {
		if !strings.Contains(err.Error(), w) {
			t.Fatalf("error %q does not say %q", err, w)
		}
	}
}

func TestAgentWithoutIntentIsNoContractNotAnError(t *testing.T) {
	m := parse(t, accepted)
	if got := m.StateOf(agentB, "2026-10-02"); got != NoContract {
		t.Fatalf("StateOf(agent without contract) = %q, want %q", got, NoContract)
	}
	var none Manifest
	if got := none.StateOf(agentA, "2026-10-02"); got != NoContract {
		t.Fatalf("StateOf with no manifest at all = %q, want %q", got, NoContract)
	}
	if err := m.Check(map[string]bool{agentA: true, agentB: true}); err != nil {
		t.Fatalf("an agent without a contract made Check fail: %v", err)
	}
}

func TestDraftOrExpiredIntentDoesNotCount(t *testing.T) {
	m := parse(t, accepted)
	if got := m.StateOf(agentA, "2026-10-02"); got != InForce || !got.Binds() {
		t.Fatalf("accepted contract before its expiry: state %q, binds %v", got, got.Binds())
	}
	if got := m.StateOf(agentA, "2027-04-01"); got != InForce {
		t.Fatalf("on its expiry day the contract is %q, want %q", got, InForce)
	}
	if got := m.StateOf(agentA, "2027-04-02"); got != Expired || got.Binds() {
		t.Fatalf("after its expiry: state %q, binds %v; want %q and false", got, got.Binds(), Expired)
	}
	draft := strings.Replace(accepted, `"status": "accepted",
      "accepted_by": "@ana",
      "accepted_at": "2026-10-01",`, `"status": "draft",
      "confidence": "inferred",`, 1)
	d := parse(t, draft)
	if got := d.StateOf(agentA, "2026-10-02"); got != Draft || got.Binds() {
		t.Fatalf("draft: state %q, binds %v; want %q and false", got, got.Binds(), Draft)
	}
}

func TestIntentAmountsAreIntegersInMinorUnits(t *testing.T) {
	parseFails(t, strings.Replace(accepted, `"amount": 50000`, `"amount": 500.50`, 1), "amount", "integer")
	parseFails(t, strings.Replace(accepted, `"amount": 50000`, `"amount": 5e4`, 1), "amount", "integer")
	parseFails(t, strings.Replace(accepted, `"amount": 50000`, `"amount": -1`, 1), "amount")
	parseFails(t, strings.Replace(accepted, `"currency": "EUR"}}`, `"currency": "euros"}}`, 1), "currency")
	m := parse(t, accepted)
	if got := m.Contracts[0].Limits[0].PerOperation.Amount; got != 50000 {
		t.Fatalf("amount = %d, want 50000 (minor units)", got)
	}
}

func TestIntentValidationRejectsACapabilityBothAllowedAndDenied(t *testing.T) {
	parseFails(t, strings.Replace(accepted, `"deny": ["customer.delete"]`, `"deny": ["customer.delete", "money.refund"]`, 1),
		"money.refund", "allow", "deny")
}

// ADR 0004, round of step 1.2c (high 4): a contract whose agent is gone is an
// input error that names the agent, never ignored.
func TestIntentOrphanContractIsAnInputError(t *testing.T) {
	m := parse(t, accepted)
	err := m.Check(map[string]bool{agentB: true})
	if err == nil || !strings.Contains(err.Error(), agentA) {
		t.Fatalf("Check with the agent gone: err = %v, want an error naming %s", err, agentA)
	}
}

func TestIntentRejectsAnotherACMVersion(t *testing.T) {
	parseFails(t, strings.Replace(accepted, `"acm_version": 0`, `"acm_version": 1`, 1), "acm_version")
	parseFails(t, strings.Replace(accepted, `"acm_version": 0,`, ``, 1), "acm_version")
}

func TestIntentCapabilityFormHasNoWildcards(t *testing.T) {
	for _, bad := range []string{`customer.*`, `Customer.read`, `customer`, `customer.read.all`, `1customer.read`, `customer.`} {
		parseFails(t, strings.Replace(accepted, `"customer.read"`, `"`+bad+`"`, 1), bad)
	}
}

func TestIntentAcceptedNeedsWhoAndWhen(t *testing.T) {
	parseFails(t, strings.Replace(accepted, `"accepted_by": "@ana",`, ``, 1), "accepted_by")
	parseFails(t, strings.Replace(accepted, `"accepted_at": "2026-10-01",`, ``, 1), "accepted_at")
	parseFails(t, strings.Replace(accepted, `"accepted_at": "2026-10-01"`, `"accepted_at": "1 Oct 2026"`, 1), "accepted_at")
	parseFails(t, strings.Replace(accepted, `"owner": "@ana",`, ``, 1), "owner")
	parseFails(t, strings.Replace(accepted, `"expires": "2027-04-01",`, ``, 1), "expires")
}

// A draft is what a tool proposes: it carries confidence inferred and no
// acceptance (ADR 0004).
func TestIntentDraftMustBeInferredAndUnaccepted(t *testing.T) {
	parseFails(t, strings.Replace(accepted, `"status": "accepted",`, `"status": "draft",`, 1), "draft")
	parseFails(t, strings.Replace(accepted, `"status": "accepted",`, `"status": "approved",`, 1), "status")
	parseFails(t, strings.Replace(accepted, `"status": "accepted",`, `"status": "accepted", "confidence": "inferred",`, 1), "confidence")
}

func TestIntentEgressIsAHostName(t *testing.T) {
	for _, bad := range []string{`https://api.stripe.com`, `api.stripe.com/v1`, `api.stripe.com:443`, `API.stripe.com`, `*`, `stripe`} {
		parseFails(t, strings.Replace(accepted, `"api.stripe.com"`, `"`+bad+`"`, 1), "egress")
	}
}

func TestIntentUnknownFieldIsAnError(t *testing.T) {
	parseFails(t, strings.Replace(accepted, `"owner": "@ana",`, `"owner": "@ana", "ownr": "x",`, 1), "ownr")
}

func TestIntentOneContractPerAgent(t *testing.T) {
	two := strings.Replace(accepted, `  ]
}`, `  , {"agent": "0123456789abcdef", "status": "draft", "confidence": "inferred", "owner": "@b", "expires": "2027-01-01", "allow": [], "deny": [], "limits": [], "egress": []}]
}`, 1)
	parseFails(t, two, agentA)
}

func TestIntentStringsAreReadAsNFC(t *testing.T) {
	m := parse(t, strings.Replace(accepted, `"owner": "@ana"`, "\"owner\": \"@aná\"", 1))
	if got := m.Contracts[0].Owner; got != "@aná" {
		t.Fatalf("owner = %q, want it in NFC %q", got, "@aná")
	}
}
