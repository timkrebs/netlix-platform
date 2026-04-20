package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestProxyStripsPrefix(t *testing.T) {
	var seenPath string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seenPath = r.URL.Path
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, "ok")
	}))
	defer upstream.Close()

	target, _ := url.Parse(upstream.URL)
	h := proxy(target, "/api/catalog")

	mux := http.NewServeMux()
	mux.Handle("/api/catalog/", h)

	req := httptest.NewRequest(http.MethodGet, "/api/catalog/products/42", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200", rec.Code)
	}
	if seenPath != "/products/42" {
		t.Fatalf("upstream path: got %q want %q", seenPath, "/products/42")
	}
}

func TestProxyBadGateway(t *testing.T) {
	target, _ := url.Parse("http://127.0.0.1:1") // closed port
	h := proxy(target, "/api/auth")

	mux := http.NewServeMux()
	mux.Handle("/api/auth/", h)

	req := httptest.NewRequest(http.MethodGet, "/api/auth/login", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status: got %d want 502", rec.Code)
	}
}

func TestSPAFallbackToIndex(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"), []byte("<html>spa</html>"), 0o644); err != nil {
		t.Fatalf("write index: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "asset.js"), []byte("console.log(1)"), 0o644); err != nil {
		t.Fatalf("write asset: %v", err)
	}

	h := spaHandler(dir)

	t.Run("known asset served directly", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/asset.js", nil)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("status: got %d want 200", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "console.log") {
			t.Fatalf("body: %q", rec.Body.String())
		}
	})

	t.Run("unknown route falls back to index.html", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/orders/new", nil)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("status: got %d want 200", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "spa") {
			t.Fatalf("body: %q", rec.Body.String())
		}
	})
}
