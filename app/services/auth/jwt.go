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
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := t.SignedString(s.cfg.jwtSecret)
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
		return s.cfg.jwtSecret, nil
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
