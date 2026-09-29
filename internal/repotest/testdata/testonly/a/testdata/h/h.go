// Package h hides in testdata and only the tests of a import it.
package h

import "testing"

// Maybe does nothing.
func Maybe(t *testing.T) { t.Helper() }
