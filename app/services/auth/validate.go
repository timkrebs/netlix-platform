package main

import (
	"errors"
	"regexp"
	"strings"
	"unicode"
)

// emailRegex covers >99% of real-world emails without trying to be RFC-perfect.
// We trade a fuzzy edge for a tight, fast check and rely on the actual
// signup-confirmation email (when added) to weed out anything weirder.
var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

func validateEmail(s string) error {
	if len(s) == 0 || len(s) > 254 {
		return errors.New("email length must be 1-254 characters")
	}
	if !emailRegex.MatchString(s) {
		return errors.New("email is not a valid address")
	}
	return nil
}

// validatePassword enforces a "good enough" baseline: at least 10
// chars, with at least three of the four character classes (upper,
// lower, digit, symbol). Stricter than the original 8-char floor;
// looser than NIST 800-63B (which we'd switch to once we add
// breached-password lookup via HIBP).
func validatePassword(p string) error {
	if len(p) < 10 {
		return errors.New("password must be at least 10 characters")
	}
	if len(p) > 128 {
		return errors.New("password must be at most 128 characters")
	}
	var hasUpper, hasLower, hasDigit, hasSymbol bool
	for _, r := range p {
		switch {
		case unicode.IsUpper(r):
			hasUpper = true
		case unicode.IsLower(r):
			hasLower = true
		case unicode.IsDigit(r):
			hasDigit = true
		case strings.ContainsRune("!@#$%^&*()-_=+[]{};:'\",.<>/?`~\\|", r):
			hasSymbol = true
		}
	}
	classes := boolToInt(hasUpper) + boolToInt(hasLower) + boolToInt(hasDigit) + boolToInt(hasSymbol)
	if classes < 3 {
		return errors.New("password must include at least three of: uppercase, lowercase, digit, symbol")
	}
	return nil
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
