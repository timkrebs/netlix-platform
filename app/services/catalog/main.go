package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	_ "github.com/lib/pq"
)

type Product struct {
	ID          int64  `json:"id"`
	SKU         string `json:"sku"`
	Title       string `json:"title"`
	Description string `json:"description"`
	PriceCents  int    `json:"price_cents"`
	ImageURL    string `json:"image_url"`
	Stock       int    `json:"stock"`
}

type server struct {
	db *sql.DB
}

func main() {
	dsn := buildDSN()
	db, err := openDB(dsn)
	if err != nil {
		log.Fatalf("catalog: db open: %v", err)
	}
	defer db.Close()

	srv := &server{db: db}

	mux := http.NewServeMux()
	srv.routes(mux)
	mux.Handle("/metrics", metricsHandler())

	addr := envDefault("LISTEN_ADDR", "0.0.0.0:8080")
	httpSrv := &http.Server{
		Addr:              addr,
		Handler:           recoverMiddleware(metricsMiddleware(mux)),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       30 * time.Second,
	}

	go func() {
		log.Printf("catalog: listening on %s", addr)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("catalog: server failed: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Printf("catalog: shutdown signal received, draining for 20s")

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(ctx); err != nil {
		log.Printf("catalog: shutdown error: %v", err)
	}
}

// recoverMiddleware converts handler panics (nil deref, bad rows scan,
// etc.) to 500 responses instead of crashing the pod.
func recoverMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("catalog: panic %v on %s %s", rec, r.Method, r.URL.Path)
				writeErr(w, http.StatusInternalServerError, "internal")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func (s *server) routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", health)
	mux.HandleFunc("GET /ready", s.ready)
	mux.HandleFunc("GET /products", s.listProducts)
	mux.HandleFunc("GET /products/{id}", s.getProduct)
}

func (s *server) listProducts(w http.ResponseWriter, r *http.Request) {
	// Bounded pagination. Previously unbounded SELECT * would ship the
	// entire products table on every request — under load that's both
	// a network amplifier and a DB hot path. Default 50, hard cap 500.
	limit := clampInt(parseIntQuery(r, "limit", 50), 1, 500)
	offset := maxInt(parseIntQuery(r, "offset", 0), 0)

	rows, err := s.db.QueryContext(r.Context(),
		`SELECT id, sku, title, description, price_cents, image_url, stock
		   FROM products ORDER BY id LIMIT $1 OFFSET $2`, limit, offset)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "query failed")
		log.Printf("catalog: list query: %v", err)
		return
	}
	defer rows.Close()

	out := make([]Product, 0, limit)
	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.SKU, &p.Title, &p.Description, &p.PriceCents, &p.ImageURL, &p.Stock); err != nil {
			writeErr(w, http.StatusInternalServerError, "scan failed")
			return
		}
		out = append(out, p)
	}
	writeJSON(w, http.StatusOK, out)
}

func parseIntQuery(r *http.Request, key string, fallback int) int {
	if v := r.URL.Query().Get(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func (s *server) getProduct(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "invalid id")
		return
	}

	var p Product
	err = s.db.QueryRowContext(r.Context(),
		`SELECT id, sku, title, description, price_cents, image_url, stock
		   FROM products WHERE id = $1`, id).
		Scan(&p.ID, &p.SKU, &p.Title, &p.Description, &p.PriceCents, &p.ImageURL, &p.Stock)
	if errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "product not found")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "query failed")
		log.Printf("catalog: get query: %v", err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "healthy"})
}

func (s *server) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.db.PingContext(ctx); err != nil {
		writeErr(w, http.StatusServiceUnavailable, "db unreachable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func openDB(dsn string) (*sql.DB, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(intEnvDefault("DB_MAX_OPEN_CONNS", 25))
	db.SetMaxIdleConns(intEnvDefault("DB_MAX_IDLE_CONNS", 10))
	db.SetConnMaxLifetime(5 * time.Minute)
	return db, nil
}

func intEnvDefault(k string, d int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return d
}

func buildDSN() string {
	if v := os.Getenv("DATABASE_URL"); v != "" {
		return v
	}
	return "host=" + envDefault("DB_HOST", "postgres") +
		" port=" + envDefault("DB_PORT", "5432") +
		" user=" + envDefault("DB_USER", "netlix") +
		" password=" + envDefault("DB_PASSWORD", "netlix") +
		" dbname=" + envDefault("DB_NAME", "netlix") +
		" sslmode=" + envDefault("DB_SSLMODE", "disable")
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

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}
