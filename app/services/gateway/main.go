package main

import (
	"encoding/json"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	catalogURL := mustURL("CATALOG_URL", "http://catalog:8080")
	authURL := mustURL("AUTH_URL", "http://auth:8080")
	ordersURL := mustURL("ORDERS_URL", "http://orders:8080")
	staticDir := envDefault("STATIC_DIR", "/var/www/spa")
	addr := envDefault("LISTEN_ADDR", "0.0.0.0:8080")

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

	mux.Handle("/metrics", metricsHandler())
	mux.Handle("/", spaHandler(staticDir))

	srv := &http.Server{
		Addr:         addr,
		Handler:      metricsMiddleware(logRequests(mux)),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("gateway: listening on %s (spa=%s, catalog=%s, auth=%s, orders=%s)",
		addr, staticDir, catalogURL, authURL, ordersURL)
	log.Fatal(srv.ListenAndServe())
}

func proxy(target *url.URL, stripPrefix string) http.Handler {
	rp := httputil.NewSingleHostReverseProxy(target)
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
