// Package intent reads and validates the capability contract of each agent:
// the Agent Capability Manifest (ACM) version 0 of docs/spec/acm.md, written
// by a person in actaira.intent.json and copied into the intent block of
// actaira.lock (ADR 0004). It is public API: actaira-cloud imports it.
package intent

import (
	"bytes"
	"encoding/json/jsontext"
	jsonv2 "encoding/json/v2"
	"errors"
	"fmt"
	"io"
	"reflect"
	"regexp"
	"strings"
	"time"

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
	ACMVersion *int64         `json:"acm_version"`
	Contracts  *[]rawContract `json:"contracts"`
}

type rawContract struct {
	Agent      string     `json:"agent"`
	Status     string     `json:"status"`
	Confidence *string    `json:"confidence"`
	AcceptedBy *string    `json:"accepted_by"`
	AcceptedAt *string    `json:"accepted_at"`
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
	Amount   *int64 `json:"amount"`
	Currency string `json:"currency"`
}

type rawPeriod struct {
	Period   string  `json:"period"`
	Amount   *int64  `json:"amount"`
	Currency *string `json:"currency"`
	Count    *int64  `json:"count"`
}

var (
	capabilityRE = regexp.MustCompile(`^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`)
	currencyRE   = regexp.MustCompile(`^[A-Z]{3}$`)
	agentRE      = regexp.MustCompile(`^[0-9a-f]{16}$`)
	hostRE       = regexp.MustCompile(`^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$`)
)

// Parse reads an ACM version 0 document. It reads with encoding/json/v2 of the
// standard library (https://pkg.go.dev/encoding/json/v2), which rejects a
// repeated or miscased member name, invalid UTF-8 and numbers that are not
// integers written as digits (F-0030); and it rejects null, an empty optional
// field, unknown members and everything docs/spec/acm.md forbids, naming the
// field. Text is read as Unicode NFC, like the rest of actaira.lock (ADR 0002).
func Parse(data []byte) (Manifest, error) {
	if err := noNull(data); err != nil {
		return Manifest{}, err
	}
	var raw rawManifest
	if err := jsonv2.Unmarshal(data, &raw, jsonv2.RejectUnknownMembers(true)); err != nil {
		var se *jsonv2.SemanticError
		if errors.As(err, &se) && se.GoType == reflect.TypeFor[int64]() {
			return Manifest{}, fmt.Errorf("intent: %s: not an integer written with digits (amounts are in minor units): %w", se.JSONPointer, err)
		}
		return Manifest{}, fmt.Errorf("intent: %w", err)
	}
	if raw.ACMVersion == nil {
		return Manifest{}, fmt.Errorf("intent: acm_version: required, %d", ACMVersion)
	}
	if *raw.ACMVersion != ACMVersion {
		return Manifest{}, fmt.Errorf("intent: acm_version: %d is not supported, only %d", *raw.ACMVersion, ACMVersion)
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

// noNull rejects a null anywhere in the document: the schema never allows it,
// and decoding it would look like a missing field. Repeated names and invalid
// UTF-8 are left to jsonv2.Unmarshal, the one place that rejects them.
func noNull(data []byte) error {
	dec := jsontext.NewDecoder(bytes.NewReader(data), jsontext.AllowDuplicateNames(true), jsontext.AllowInvalidUTF8(true))
	for {
		tok, err := dec.ReadToken()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("intent: %w", err)
		}
		if tok.Kind() == 'n' {
			return fmt.Errorf("intent: null at %s is not allowed", dec.StackPointer())
		}
	}
}

// optional returns the value of an optional string field, which may be
// missing but never empty.
func optional(field string, p *string) (string, error) {
	if p == nil {
		return "", nil
	}
	if *p == "" {
		return "", fmt.Errorf("%s: empty; leave the field out instead", field)
	}
	return nfc(*p), nil
}

// checkDay checks that s is a real calendar day, YYYY-MM-DD.
func checkDay(field, s string) error {
	if _, err := time.Parse(time.DateOnly, s); err != nil {
		return fmt.Errorf("%s: %q is not a day YYYY-MM-DD", field, s)
	}
	return nil
}

func contract(rc rawContract) (Contract, error) {
	c := Contract{
		Agent:   nfc(rc.Agent),
		Status:  nfc(rc.Status),
		Owner:   nfc(rc.Owner),
		Expires: nfc(rc.Expires),
		Allow:   nfcAll(rc.Allow),
		Deny:    nfcAll(rc.Deny),
		Egress:  nfcAll(rc.Egress),
	}
	var err error
	if c.Confidence, err = optional("confidence", rc.Confidence); err != nil {
		return Contract{}, err
	}
	if c.AcceptedBy, err = optional("accepted_by", rc.AcceptedBy); err != nil {
		return Contract{}, err
	}
	if c.AcceptedAt, err = optional("accepted_at", rc.AcceptedAt); err != nil {
		return Contract{}, err
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
		if err := checkDay("accepted_at", c.AcceptedAt); err != nil {
			return Contract{}, err
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
	if err := checkDay("expires", c.Expires); err != nil {
		return Contract{}, err
	}
	allowed := map[string]bool{}
	denied := map[string]bool{}
	for _, list := range []struct {
		name string
		caps []string
		set  map[string]bool
	}{{"allow", c.Allow, allowed}, {"deny", c.Deny, denied}} {
		for _, cap := range list.caps {
			if !capabilityRE.MatchString(cap) {
				return Contract{}, fmt.Errorf("%s: %q is not a capability <resource>.<action> (no wildcards)", list.name, cap)
			}
			if list.set[cap] {
				return Contract{}, fmt.Errorf("%s: %q appears twice", list.name, cap)
			}
			list.set[cap] = true
			if list.name == "deny" && allowed[cap] {
				return Contract{}, fmt.Errorf("%q is both in allow and in deny", cap)
			}
		}
	}
	for i, rl := range rc.Limits {
		l, err := limit(rl)
		if err != nil {
			return Contract{}, fmt.Errorf("limits[%d]: %w", i, err)
		}
		// A limit on a capability that is not allowed would leave the real one
		// without a limit (a typo) or limit what is denied anyway.
		if !allowed[l.Capability] {
			return Contract{}, fmt.Errorf("limits[%d]: %q is not in allow; a limit only bounds an allowed capability", i, l.Capability)
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
		if rl.PerOperation.Amount == nil {
			return Limit{}, errors.New("per_operation.amount: required")
		}
		n, err := minorUnits("per_operation.amount", *rl.PerOperation.Amount)
		if err != nil {
			return Limit{}, err
		}
		cur := nfc(rl.PerOperation.Currency)
		if !currencyRE.MatchString(cur) {
			return Limit{}, fmt.Errorf("per_operation.currency: %q is not a currency code of three capital letters (ISO 4217)", cur)
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
		if (rl.PerPeriod.Amount == nil) != (rl.PerPeriod.Currency == nil) {
			return Limit{}, errors.New("per_period: amount and currency go together")
		}
		if rl.PerPeriod.Amount != nil {
			n, err := minorUnits("per_period.amount", *rl.PerPeriod.Amount)
			if err != nil {
				return Limit{}, err
			}
			p.Amount = &n
			p.Currency = nfc(*rl.PerPeriod.Currency)
			if !currencyRE.MatchString(p.Currency) {
				return Limit{}, fmt.Errorf("per_period.currency: %q is not a currency code of three capital letters (ISO 4217)", p.Currency)
			}
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

// minorUnits checks a whole, non-negative number: amounts are in the minor
// unit of their currency, and the canonical JSON has no decimals (ADR 0002).
// The decoder already refused anything not written as an integer.
func minorUnits(field string, v int64) (int64, error) {
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

// Validate checks a Manifest built in code against the same rules as Parse:
// actaira.lock never carries a contract that Parse would reject.
func (m Manifest) Validate() error {
	data, err := jsonv2.Marshal(m.Value())
	if err != nil {
		return fmt.Errorf("intent: %w", err)
	}
	_, err = Parse(data)
	return err
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

// StateOf returns the state of agent's contract on the UTC day of today. An
// agent without a contract is NoContract, not an error. The contract is still
// in force on its expiry day. Without a day (the zero time) there is no state:
// an expired contract must never look in force by accident.
func (m Manifest) StateOf(agent string, today time.Time) (State, error) {
	if today.IsZero() {
		return "", errors.New("intent: StateOf needs a day")
	}
	d := today.UTC().Format(time.DateOnly)
	for _, c := range m.Contracts {
		if c.Agent != agent {
			continue
		}
		switch {
		case c.Status == StatusDraft:
			return Draft, nil
		case c.Expires < d:
			return Expired, nil
		default:
			return InForce, nil
		}
	}
	return NoContract, nil
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
