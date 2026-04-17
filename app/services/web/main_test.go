package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func newTestMux() *http.ServeMux {
	mux := http.NewServeMux()

	name := getEnv("NAME", "web")
	message := getEnv("MESSAGE", "Hello from the web frontend")
	environment := getEnv("ENVIRONMENT", "dev")
	version := getEnv("VERSION", "unknown")
	hostname, _ := os.Hostname()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		resp := Response{
			Name:        name,
			Message:     message,
			Environment: environment,
			Version:     version,
			Hostname:    hostname,
			Timestamp:   "2026-01-01T00:00:00Z",
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
	})

	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
	})

	return mux
}

func TestHealthEndpoint(t *testing.T) {
	mux := newTestMux()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()

	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	ct := w.Header().Get("Content-Type")
	if ct != "application/json" {
		t.Fatalf("expected application/json, got %s", ct)
	}

	var body map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if body["status"] != "healthy" {
		t.Fatalf("expected status=healthy, got %s", body["status"])
	}
}

func TestReadyEndpoint(t *testing.T) {
	mux := newTestMux()
	req := httptest.NewRequest(http.MethodGet, "/ready", nil)
	w := httptest.NewRecorder()

	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var body map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if body["status"] != "ready" {
		t.Fatalf("expected status=ready, got %s", body["status"])
	}
}

func TestRootEndpoint(t *testing.T) {
	mux := newTestMux()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()

	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp Response
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}

	if resp.Name != "web" {
		t.Errorf("expected name=web, got %s", resp.Name)
	}
	if resp.Environment != "dev" {
		t.Errorf("expected environment=dev, got %s", resp.Environment)
	}
	if resp.Hostname == "" {
		t.Error("hostname should not be empty")
	}
	if resp.Timestamp == "" {
		t.Error("timestamp should not be empty")
	}
}

func TestRootEndpointWithName(t *testing.T) {
	t.Setenv("NAME", "api")
	t.Setenv("ENVIRONMENT", "staging")

	mux := newTestMux()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()

	mux.ServeHTTP(w, req)

	var resp Response
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}

	if resp.Name != "api" {
		t.Errorf("expected name=api, got %s", resp.Name)
	}
	if resp.Environment != "staging" {
		t.Errorf("expected environment=staging, got %s", resp.Environment)
	}
}

func TestNotFoundPath(t *testing.T) {
	mux := newTestMux()
	req := httptest.NewRequest(http.MethodGet, "/nonexistent", nil)
	w := httptest.NewRecorder()

	mux.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

func TestGetEnvDefault(t *testing.T) {
	val := getEnv("NONEXISTENT_VAR_12345", "fallback")
	if val != "fallback" {
		t.Errorf("expected fallback, got %s", val)
	}
}

func TestGetEnvOverride(t *testing.T) {
	t.Setenv("TEST_OVERRIDE_VAR", "custom")
	val := getEnv("TEST_OVERRIDE_VAR", "fallback")
	if val != "custom" {
		t.Errorf("expected custom, got %s", val)
	}
}
