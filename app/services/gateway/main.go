package main

import (
	"context"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Pooled HTTP transport shared across all three reverse-proxy targets.
// Default net/http.Transport caps idle connections per host at 2, so at
// 20k concurrent requests the gateway opens/closes ~10k conns per
// backend per second, exhausting ephemeral ports and backend
// file-descriptors. These tuned values hold a pool of ~32 idle conns
// per backend host and reuse aggressively.
var proxyTransport = &http.Transport{
	Proxy: http.ProxyFromEnvironment,
	DialContext: (&net.Dialer{
		Timeout:   5 * time.Second,
		KeepAlive: 30 * time.Second,
	}).DialContext,
	MaxIdleConns:          200,
	MaxIdleConnsPerHost:   32,
	IdleConnTimeout:       90 * time.Second,
	TLSHandshakeTimeout:   5 * time.Second,
	ExpectContinueTimeout: 1 * time.Second,
	ForceAttemptHTTP2:     true,
}

func main() {
	catalogURL := mustURL("CATALOG_URL", "http://catalog:8080")
	authURL := mustURL("AUTH_URL", "http://auth:8080")
	ordersURL := mustURL("ORDERS_URL", "http://orders:8080")
	staticDir := envDefault("STATIC_DIR", "/var/www/spa")
	addr := envDefault("LISTEN_ADDR", "0.0.0.0:8080")
	flagsPath := envDefault("FEATURE_FLAGS_PATH", "/etc/shop/flags.json")

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "healthy"})
	})
	mux.HandleFunc("GET /ready", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})

	// /api/catalog/* → catalog service (strip /api/catalog prefix)
	mux.Handle("/api/catalog/", proxy(catalogURL, "/api/catalog"))
	// /api/auth/* → auth service
	mux.Handle("/api/auth/", proxy(authURL, "/api/auth"))
	// /api/orders/* → orders service
	mux.Handle("/api/orders/", proxy(ordersURL, "/api/orders"))

	// /api/flags → KVv2-backed feature flags read from a VSO-projected
	// file. No auth, short cache, defaults on read errors.
	mux.HandleFunc("GET /api/flags", flagsHandler(flagsPath))

	mux.Handle("/metrics", metricsHandler())
	mux.Handle("/", spaHandler(staticDir))

	srv := &http.Server{
		Addr:              addr,
		Handler:           recoverMiddleware(metricsMiddleware(logRequests(mux))),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// Run the listener in a goroutine so main() can wait for SIGTERM.
	// Without this, K8s rolling updates / HPA scale-down kills in-flight
	// requests as soon as the pod gets SIGTERM.
	go func() {
		log.Printf("gateway: listening on %s (spa=%s, catalog=%s, auth=%s, orders=%s)",
			addr, staticDir, catalogURL, authURL, ordersURL)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("gateway: server failed: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Printf("gateway: shutdown signal received, draining for 20s")

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("gateway: shutdown error: %v", err)
	}
}

func proxy(target *url.URL, stripPrefix string) http.Handler {
	rp := httputil.NewSingleHostReverseProxy(target)
	rp.Transport = proxyTransport // shared pooled transport, not default
	originalDirector := rp.Director
	rp.Director = func(r *http.Request) {
		r.URL.Path = strings.TrimPrefix(r.URL.Path, stripPrefix)
		if r.URL.Path == "" {
			r.URL.Path = "/"
		}
		originalDirector(r)
		r.Host = target.Host
	}
	rp.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, err error) {
		log.Printf("gateway: proxy error to %s: %v", target.Host, err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream unavailable"})
	}
	return rp
}

// recoverMiddleware catches panics from downstream handlers (bad
// request bodies, nil map access, etc.) and converts them to 500s
// instead of crashing the pod. K8s would restart the pod on a crash,
// which during high load cascades into dropped connections for other
// pods as they briefly become the only receivers.
func recoverMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("gateway: panic %v on %s %s", rec, r.Method, r.URL.Path)
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal"})
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// spaHandler serves static files from dir, falling back to index.html
// for any path that doesn't map to a file (so client-side routing works).
func spaHandler(dir string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		clean := filepath.Clean(r.URL.Path)
		if clean == "/" {
			clean = "/index.html"
		}
		full := filepath.Join(dir, clean)
		// Prevent path traversal: full must remain inside dir.
		if !strings.HasPrefix(full, filepath.Clean(dir)+string(os.PathSeparator)) && full != filepath.Clean(dir) {
			http.NotFound(w, r)
			return
		}
		if info, err := os.Stat(full); err == nil && !info.IsDir() {
			http.ServeFile(w, r, full)
			return
		}
		// Fallback to index.html for SPA routes.
		http.ServeFile(w, r, filepath.Join(dir, "index.html"))
	})
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

func mustURL(envKey, fallback string) *url.URL {
	raw := envDefault(envKey, fallback)
	u, err := url.Parse(raw)
	if err != nil {
		log.Fatalf("gateway: invalid %s=%q: %v", envKey, raw, err)
	}
	return u
}

func envDefault(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// flagsHandler serves the contents of the VSO-projected feature-flag
// file with a short in-memory cache. The whole point of this endpoint
// is to make Vault → file → API → SPA propagation observable without
// restarting the pod, so:
//   - Cache TTL is intentionally short (5s) — caps load if the SPA
//     poll goes wild but small enough that the demo "feels" instant
//     once the file has been refreshed by the kubelet.
//   - Read failures and invalid JSON do NOT 500 — we serve a
//     conservative default so the UI keeps working if VSO is mid-sync,
//     the file is half-written, or the volume isn't mounted.
//   - We validate JSON before caching to avoid serving (and caching) a
//     half-written read.
func flagsHandler(path string) http.HandlerFunc {
	const ttl = 5 * time.Second
	defaultBody := []byte(`{"showPromoBanner":false,"promoText":""}`)

	var (
		mu       sync.RWMutex
		cached   []byte
		cachedAt time.Time
	)

	read := func() []byte {
		mu.RLock()
		if time.Since(cachedAt) < ttl && cached != nil {
			b := cached
			mu.RUnlock()
			return b
		}
		mu.RUnlock()

		mu.Lock()
		defer mu.Unlock()
		if time.Since(cachedAt) < ttl && cached != nil {
			return cached
		}

		body, err := os.ReadFile(path)
		if err != nil {
			log.Printf("gateway: flags read failed (%s), serving defaults: %v", path, err)
			cached = defaultBody
			cachedAt = time.Now()
			return cached
		}
		if !json.Valid(body) {
			log.Printf("gateway: flags file %s is not valid JSON (likely mid-write), serving defaults", path)
			cached = defaultBody
			cachedAt = time.Now()
			return cached
		}
		cached = body
		cachedAt = time.Now()
		return cached
	}

	return func(w http.ResponseWriter, _ *http.Request) {
		body := read()
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "max-age=5, public")
		_, _ = w.Write(body)
	}
}
