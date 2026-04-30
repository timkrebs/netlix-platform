package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// tokenClaims is the parsed view of a JWT we issue. The JTI (JWT ID)
// uniquely identifies each token so we can revoke it via the
// revoked_tokens table without invalidating every other live session.
type tokenClaims struct {
	UserID      int64
	Email       string
	JTI         string
	ExpiresUnix int64
}

func (s *server) issueToken(userID int64, email string) (string, time.Time, error) {
	jti, err := newJTI()
	if err != nil {
		return "", time.Time{}, err
	}
	exp := time.Now().Add(s.cfg.accessTTL)
	claims := jwt.MapClaims{
		"sub":   userID,
		"email": email,
		"jti":   jti,
		"iat":   time.Now().Unix(),
		"exp":   exp.Unix(),
		"iss":   "netlix-auth",
	}
	// Sign with the currently-active key from the JWKS. The kid header
	// lets the verifier route to the right key after a rotation —
	// orders' parseToken does the same lookup. After a Vault key
	// rotation, this method starts using the new key on its next call
	// (no pod restart) because PrimaryKey() reads the JWKS via RWMutex.
	kid, key := s.cfg.jwks.PrimaryKey()
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	t.Header["kid"] = kid
	signed, err := t.SignedString(key)
	if err != nil {
		return "", time.Time{}, err
	}
	return signed, exp, nil
}

// parseToken validates the signature, expiry, and required claims.
// Revocation is checked separately by the auth middleware so unit
// tests can exercise pure JWT logic without a DB.
func (s *server) parseToken(raw string) (*tokenClaims, error) {
	t, err := jwt.Parse(raw, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method")
		}
		// Look up the key by kid header. Tokens issued before the
		// Phase 6.2 rollout have no kid; KeyByID falls back to the
		// primary key in that case.
		kid, _ := t.Header["kid"].(string)
		return s.cfg.jwks.KeyByID(kid)
	})
	if err != nil || !t.Valid {
		return nil, errors.New("invalid token")
	}
	mc, ok := t.Claims.(jwt.MapClaims)
	if !ok {
		return nil, errors.New("invalid claims")
	}
	sub, ok := mc["sub"].(float64)
	if !ok {
		return nil, errors.New("missing sub claim")
	}
	jti, _ := mc["jti"].(string)
	if jti == "" {
		return nil, errors.New("missing jti claim")
	}
	exp, _ := mc["exp"].(float64)
	email, _ := mc["email"].(string)
	return &tokenClaims{
		UserID:      int64(sub),
		Email:       email,
		JTI:         jti,
		ExpiresUnix: int64(exp),
	}, nil
}

func (s *server) isRevoked(ctx context.Context, jti string) (bool, error) {
	var exists bool
	err := s.db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM revoked_tokens WHERE jti = $1)`, jti).
		Scan(&exists)
	return exists, err
}

func newJTI() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
