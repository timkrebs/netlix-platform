package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"sync"
	"time"
)

// jwksDocument matches the shape that VSO writes from the
// secret/netlix/jwt KVv2 path. Schema mirrors the auth service's
// jwks.go; orders only needs Keys for verification (it never signs).
//
//	{
//	  "primary_kid": "v2",
//	  "keys": {
//	    "v2": "<HMAC secret>",
//	    "v1": "<HMAC secret>"
//	  }
//	}
type jwksDocument struct {
	PrimaryKID string            `json:"primary_kid"`
	Keys       map[string]string `json:"keys"`
}

// JWKSManager keeps the active key set in memory and hot-reloads it
// from a file on a 30-second poll. Verify-only — orders never issues
// tokens.
type JWKSManager struct {
	path         string
	pollInterval time.Duration

	mu      sync.RWMutex
	current jwksDocument
}

func NewJWKSManager(path string) (*JWKSManager, error) {
	m := &JWKSManager{
		path:         path,
		pollInterval: 30 * time.Second,
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
			// Keep last known good keyset on transient read errors.
			log.Printf("orders: jwks reload failed; keeping previous keyset: %v", err)
		}
	}
}

// KeyByID returns the secret matching kid for verification. An empty
// kid (legacy tokens issued before Phase 6.2) falls through to the
// primary — best-effort verification until the legacy token expires.
func (m *JWKSManager) KeyByID(kid string) ([]byte, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if kid == "" {
		return []byte(m.current.Keys[m.current.PrimaryKID]), nil
	}
	key, ok := m.current.Keys[kid]
	if !ok {
		return nil, fmt.Errorf("kid %q not in current JWKS keyset", kid)
	}
	return []byte(key), nil
}
