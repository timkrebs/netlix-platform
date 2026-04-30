package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"sync"
	"time"
)

// jwksDocument is the on-disk JSON shape that VSO writes to the
// JWT_KEYS_PATH file. The whole document is the verbatim contents of
// the `keys` field in the KVv2 secret at secret/netlix/jwt — see
// terraform/components/vault-config/kv.tf and
// app/manifests/shop/vault-secrets.yaml's shop-jwt VaultStaticSecret
// template.
//
// Schema:
//
//	{
//	  "primary_kid": "v2",
//	  "keys": {
//	    "v2": "<64-char HMAC secret>",
//	    "v1": "<64-char HMAC secret>"   // verifying-only, kept until
//	                                    // all v1-signed tokens expire
//	  }
//	}
type jwksDocument struct {
	PrimaryKID string            `json:"primary_kid"`
	Keys       map[string]string `json:"keys"`
}

// JWKSManager owns the in-memory copy of the active JWT key set and
// hot-reloads it from JWT_KEYS_PATH on a 30-second poll. Hot reload
// is what makes Vault key rotation a no-restart operation: VSO writes
// new content into the K8s Secret → kubelet refreshes the projected
// file → JWKSManager picks up the change on its next tick → Sign()
// switches to the new primary key, Verify() still accepts tokens
// signed with previously-active keys until they expire.
type JWKSManager struct {
	path         string
	pollInterval time.Duration
	logger       *slog.Logger

	mu      sync.RWMutex
	current jwksDocument
}

// NewJWKSManager loads the key set from path once eagerly (so that
// any startup misconfiguration fails fast in main()) and then starts
// a background poll.
func NewJWKSManager(path string, logger *slog.Logger) (*JWKSManager, error) {
	m := &JWKSManager{
		path:         path,
		pollInterval: 30 * time.Second,
		logger:       logger,
	}
	if err := m.reload(); err != nil {
		return nil, fmt.Errorf("initial JWKS load from %s: %w", path, err)
	}
	go m.poll()
	return m, nil
}

func (m *JWKSManager) reload() error {
	data, err := os.ReadFile(m.path)
	if err != nil {
		return err
	}
	var doc jwksDocument
	if err := json.Unmarshal(data, &doc); err != nil {
		return fmt.Errorf("parse JWKS: %w", err)
	}
	if doc.PrimaryKID == "" {
		return errors.New("JWKS document has empty primary_kid")
	}
	if _, ok := doc.Keys[doc.PrimaryKID]; !ok {
		return fmt.Errorf("JWKS primary_kid %q not present in keys map", doc.PrimaryKID)
	}
	for kid, key := range doc.Keys {
		if key == "" {
			return fmt.Errorf("JWKS key %q is empty", kid)
		}
	}
	m.mu.Lock()
	m.current = doc
	m.mu.Unlock()
	return nil
}

func (m *JWKSManager) poll() {
	t := time.NewTicker(m.pollInterval)
	defer t.Stop()
	for range t.C {
		if err := m.reload(); err != nil {
			// Don't crash on transient read failures — keep last
			// known good keys in memory; verify() still works.
			m.logger.Warn("jwks reload failed; keeping previous keyset", "err", err, "path", m.path)
		}
	}
}

// PrimaryKey returns the kid + secret of the key currently designated
// for signing. New tokens get this kid in their JWT header.
func (m *JWKSManager) PrimaryKey() (kid string, key []byte) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.current.PrimaryKID, []byte(m.current.Keys[m.current.PrimaryKID])
}

// KeyByID returns the secret matching kid for verification. If kid is
// the empty string (legacy tokens issued before this rollout had no
// `kid` header) we fall back to the primary key — that's the
// best-effort verification, and once those tokens expire they're gone.
func (m *JWKSManager) KeyByID(kid string) ([]byte, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if kid == "" {
		// Legacy token (pre-Phase-6.2 shape with no kid header).
		// Verify against primary; if the rotation has moved past the
		// key that signed this token, verification will simply fail
		// and the user re-logs in.
		return []byte(m.current.Keys[m.current.PrimaryKID]), nil
	}
	key, ok := m.current.Keys[kid]
	if !ok {
		return nil, fmt.Errorf("kid %q not in current JWKS keyset", kid)
	}
	return []byte(key), nil
}
