// Package intent reads and validates the capability contract of each agent:
// the Agent Capability Manifest (ACM) version 0 of docs/spec/acm.md, written
// by a person in actaira.intent.json and copied into the intent block of
// actaira.lock (ADR 0004). It is public API: actaira-cloud imports it.
package intent

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/text/unicode/norm"
)

// ACMVersion is the only manifest version that actaira.lock schema 1 accepts.
const ACMVersion = 0

// Contract statuses and the confidence of a draft (ADR 0004).
const (
	StatusAccepted     = "accepted"
	StatusDraft        = "draft"
	ConfidenceInferred = "inferred"
)

// Manifest is a parsed and valid ACM version 0 document.
type Manifest struct {
	Contracts []Contract
}

// Contract is what one agent must be able to do.
type Contract struct {
	Agent      string
	Status     string
	Confidence string // "inferred" for a draft, empty for an accepted contract
	AcceptedBy string
	AcceptedAt string // YYYY-MM-DD
	Owner      string
	Expires    string // YYYY-MM-DD
	Allow      []string
	Deny       []string
	Limits     []Limit
	Egress     []string
}

// Limit bounds one capability per operation, per period or both.
type Limit struct {
	Capability   string
	PerOperation *Amount
	PerPeriod    *Period
}

// Amount is an integer in the minor unit of an ISO 4217 currency.
type Amount struct {
	Amount   int64
	Currency string
}

// Period bounds an amount, a count or both within a day, a week or a month.
type Period struct {
	Period   string
	Amount   *int64
	Currency string
	Count    *int64
}

type rawManifest struct {
	ACMVersion *json.Number   `json:"acm_version"`
	Contracts  *[]rawContract `json:"contracts"`
}

type rawContract struct {
	Agent      string     `json:"agent"`
	Status     string     `json:"status"`
	Confidence string     `json:"confidence"`
	AcceptedBy string     `json:"accepted_by"`
	AcceptedAt string     `json:"accepted_at"`
	Owner      string     `json:"owner"`
	Expires    string     `json:"expires"`
	Allow      []string   `json:"allow"`
	Deny       []string   `json:"deny"`
	Limits     []rawLimit `json:"limits"`
	Egress     []string   `json:"egress"`
}

type rawLimit struct {
	Capability   string     `json:"capability"`
	PerOperation *rawAmount `json:"per_operation"`
	PerPeriod    *rawPeriod `json:"per_period"`
}

type rawAmount struct {
	Amount   json.Number `json:"amount"`
	Currency string      `json:"currency"`
}

type rawPeriod struct {
	Period   string       `json:"period"`
	Amount   *json.Number `json:"amount"`
	Currency string       `json:"currency"`
	Count    *json.Number `json:"count"`
}

var (
	capabilityRE = regexp.MustCompile(`^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`)
	currencyRE   = regexp.MustCompile(`^[A-Z]{3}$`)
	dateRE       = regexp.MustCompile(`^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$`)
	agentRE      = regexp.MustCompile(`^[0-9a-f]{16}$`)
	hostRE       = regexp.MustCompile(`^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$`)
)

// Parse reads an ACM version 0 document. Unknown fields, numbers that are not
// integers and everything docs/spec/acm.md forbids are errors that name the
// field. Text is read as Unicode NFC, like the rest of actaira.lock (ADR 0002).
func Parse(data []byte) (Manifest, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var raw rawManifest
	if err := dec.Decode(&raw); err != nil {
		return Manifest{}, fmt.Errorf("intent: %w", err)
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return Manifest{}, errors.New("intent: data after the manifest")
	}
	if raw.ACMVersion == nil {
		return Manifest{}, fmt.Errorf("intent: acm_version: required, %d", ACMVersion)
	}
	if v, err := raw.ACMVersion.Int64(); err != nil || v != ACMVersion {
		return Manifest{}, fmt.Errorf("intent: acm_version: %s is not supported, only %d", raw.ACMVersion, ACMVersion)
	}
	if raw.Contracts == nil {
		return Manifest{}, errors.New("intent: contracts: required")
	}
	var m Manifest
	seen := map[string]bool{}
	for i, rc := range *raw.Contracts {
		c, err := contract(rc)
		if err != nil {
			return Manifest{}, fmt.Errorf("intent: contracts[%d]: %w", i, err)
		}
		if seen[c.Agent] {
			return Manifest{}, fmt.Errorf("intent: contracts[%d]: agent %s has more than one contract", i, c.Agent)
		}
		seen[c.Agent] = true
		m.Contracts = append(m.Contracts, c)
	}
	return m, nil
}

func contract(rc rawContract) (Contract, error) {
	c := Contract{
		Agent:      nfc(rc.Agent),
		Status:     nfc(rc.Status),
		Confidence: nfc(rc.Confidence),
		AcceptedBy: nfc(rc.AcceptedBy),
		AcceptedAt: nfc(rc.AcceptedAt),
		Owner:      nfc(rc.Owner),
		Expires:    nfc(rc.Expires),
		Allow:      nfcAll(rc.Allow),
		Deny:       nfcAll(rc.Deny),
		Egress:     nfcAll(rc.Egress),
	}
	if !agentRE.MatchString(c.Agent) {
		return Contract{}, fmt.Errorf("agent: %q is not an agent id (16 lowercase hex characters)", c.Agent)
	}
	switch c.Status {
	case StatusAccepted:
		if c.Confidence != "" {
			return Contract{}, fmt.Errorf("confidence: an accepted contract carries no confidence, got %q", c.Confidence)
		}
		if c.AcceptedBy == "" {
			return Contract{}, errors.New("accepted_by: required for an accepted contract")
		}
		if !dateRE.MatchString(c.AcceptedAt) {
			return Contract{}, fmt.Errorf("accepted_at: %q is not a date YYYY-MM-DD", c.AcceptedAt)
		}
	case StatusDraft:
		if c.Confidence != ConfidenceInferred || c.AcceptedBy != "" || c.AcceptedAt != "" {
			return Contract{}, errors.New("status: a draft carries confidence inferred and no accepted_by or accepted_at")
		}
	default:
		return Contract{}, fmt.Errorf("status: %q is not accepted or draft", c.Status)
	}
	if c.Owner == "" {
		return Contract{}, errors.New("owner: required")
	}
	if !dateRE.MatchString(c.Expires) {
		return Contract{}, fmt.Errorf("expires: %q is not a date YYYY-MM-DD", c.Expires)
	}
	allowed := map[string]bool{}
	for _, list := range []struct {
		name string
		caps []string
	}{{"allow", c.Allow}, {"deny", c.Deny}} {
		seen := map[string]bool{}
		for _, cap := range list.caps {
			if !capabilityRE.MatchString(cap) {
				return Contract{}, fmt.Errorf("%s: %q is not a capability <resource>.<action> (no wildcards)", list.name, cap)
			}
			if seen[cap] {
				return Contract{}, fmt.Errorf("%s: %q appears twice", list.name, cap)
			}
			seen[cap] = true
			if list.name == "allow" {
				allowed[cap] = true
			} else if allowed[cap] {
				return Contract{}, fmt.Errorf("%q is both in allow and in deny", cap)
			}
		}
	}
	for i, rl := range rc.Limits {
		l, err := limit(rl)
		if err != nil {
			return Contract{}, fmt.Errorf("limits[%d]: %w", i, err)
		}
		c.Limits = append(c.Limits, l)
	}
	for _, host := range c.Egress {
		if !hostRE.MatchString(host) {
			return Contract{}, fmt.Errorf("egress: %q is not a lowercase host name (no scheme, path or port)", host)
		}
	}
	return c, nil
}

func limit(rl rawLimit) (Limit, error) {
	l := Limit{Capability: nfc(rl.Capability)}
	if !capabilityRE.MatchString(l.Capability) {
		return Limit{}, fmt.Errorf("capability: %q is not a capability <resource>.<action>", l.Capability)
	}
	if rl.PerOperation == nil && rl.PerPeriod == nil {
		return Limit{}, errors.New("a limit needs per_operation, per_period or both")
	}
	if rl.PerOperation != nil {
		n, err := minorUnits("per_operation.amount", rl.PerOperation.Amount)
		if err != nil {
			return Limit{}, err
		}
		cur := nfc(rl.PerOperation.Currency)
		if !currencyRE.MatchString(cur) {
			return Limit{}, fmt.Errorf("per_operation.currency: %q is not an ISO 4217 code", cur)
		}
		l.PerOperation = &Amount{Amount: n, Currency: cur}
	}
	if rl.PerPeriod != nil {
		p := Period{Period: nfc(rl.PerPeriod.Period)}
		switch p.Period {
		case "day", "week", "month":
		default:
			return Limit{}, fmt.Errorf("per_period.period: %q is not day, week or month", p.Period)
		}
		if rl.PerPeriod.Amount == nil && rl.PerPeriod.Count == nil {
			return Limit{}, errors.New("per_period: needs an amount, a count or both")
		}
		if rl.PerPeriod.Amount != nil {
			n, err := minorUnits("per_period.amount", *rl.PerPeriod.Amount)
			if err != nil {
				return Limit{}, err
			}
			p.Amount = &n
			p.Currency = nfc(rl.PerPeriod.Currency)
			if !currencyRE.MatchString(p.Currency) {
				return Limit{}, fmt.Errorf("per_period.currency: %q is not an ISO 4217 code", p.Currency)
			}
		} else if rl.PerPeriod.Currency != "" {
			return Limit{}, errors.New("per_period.currency: only with an amount")
		}
		if rl.PerPeriod.Count != nil {
			n, err := minorUnits("per_period.count", *rl.PerPeriod.Count)
			if err != nil {
				return Limit{}, err
			}
			p.Count = &n
		}
		l.PerPeriod = &p
	}
	return l, nil
}

// maxInt is the largest integer actaira.lock can hold (ADR 0002, rule 3).
const maxInt = 1<<53 - 1

// minorUnits reads a whole, non-negative number: amounts are in the minor unit
// of their currency, and the canonical JSON has no decimals (ADR 0002).
func minorUnits(field string, n json.Number) (int64, error) {
	v, err := strconv.ParseInt(n.String(), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("%s: %s is not an integer in minor units", field, n)
	}
	if v < 0 || v > maxInt {
		return 0, fmt.Errorf("%s: %d is out of range (0 to %d)", field, v, int64(maxInt))
	}
	return v, nil
}

func nfc(s string) string { return norm.NFC.String(s) }

func nfcAll(in []string) []string {
	if in == nil {
		return nil
	}
	out := make([]string, len(in))
	for i, s := range in {
		out[i] = nfc(s)
	}
	return out
}

// Check fails if a contract names an agent that is not in agents: its file
// moved or was renamed, so its id changed (ADR 0004). The person updates the
// contract in the same pull request; it is never dropped in silence.
func (m Manifest) Check(agents map[string]bool) error {
	var orphans []string
	for _, c := range m.Contracts {
		if !agents[c.Agent] {
			orphans = append(orphans, c.Agent)
		}
	}
	if len(orphans) > 0 {
		return fmt.Errorf("intent: contract for agent %s, which is not in the lockfile (moved or renamed?)", strings.Join(orphans, ", "))
	}
	return nil
}

// State is where an agent stands with its contract.
type State string

// States (docs/PLAN.md, section 0, doctrine 3; ADR 0004).
const (
	NoContract State = "no_contract"
	Draft      State = "draft"
	Expired    State = "expired"
	InForce    State = "in_force"
)

// Binds reports whether the contract counts: only an accepted contract before
// its expiry. A draft or an expired contract is shown as such, never dropped.
func (s State) Binds() bool { return s == InForce }

// StateOf returns the state of agent's contract on day today (YYYY-MM-DD). An
// agent without a contract is NoContract, not an error. The contract is still
// in force on its expiry day.
func (m Manifest) StateOf(agent, today string) State {
	for _, c := range m.Contracts {
		if c.Agent != agent {
			continue
		}
		switch {
		case c.Status == StatusDraft:
			return Draft
		case c.Expires < today:
			return Expired
		default:
			return InForce
		}
	}
	return NoContract
}

// Value returns the manifest as the value tree of the canonical JSON of
// actaira.lock (ADR 0002): the intent block, in the order it was written.
func (m Manifest) Value() any {
	contracts := []any{}
	for _, c := range m.Contracts {
		v := map[string]any{
			"agent":   c.Agent,
			"status":  c.Status,
			"owner":   c.Owner,
			"expires": c.Expires,
			"allow":   strs(c.Allow),
			"deny":    strs(c.Deny),
			"egress":  strs(c.Egress),
		}
		if c.Confidence != "" {
			v["confidence"] = c.Confidence
		}
		if c.AcceptedBy != "" {
			v["accepted_by"] = c.AcceptedBy
			v["accepted_at"] = c.AcceptedAt
		}
		limits := []any{}
		for _, l := range c.Limits {
			lv := map[string]any{"capability": l.Capability}
			if l.PerOperation != nil {
				lv["per_operation"] = map[string]any{"amount": l.PerOperation.Amount, "currency": l.PerOperation.Currency}
			}
			if l.PerPeriod != nil {
				pv := map[string]any{"period": l.PerPeriod.Period}
				if l.PerPeriod.Amount != nil {
					pv["amount"] = *l.PerPeriod.Amount
					pv["currency"] = l.PerPeriod.Currency
				}
				if l.PerPeriod.Count != nil {
					pv["count"] = *l.PerPeriod.Count
				}
				lv["per_period"] = pv
			}
			limits = append(limits, lv)
		}
		v["limits"] = limits
		contracts = append(contracts, v)
	}
	return map[string]any{"acm_version": ACMVersion, "contracts": contracts}
}

func strs(in []string) []any {
	out := make([]any, len(in))
	for i, s := range in {
		out[i] = s
	}
	return out
}
