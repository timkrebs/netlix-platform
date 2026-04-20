package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
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

	addr := envDefault("LISTEN_ADDR", "0.0.0.0:8080")
	httpSrv := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  30 * time.Second,
	}

	log.Printf("catalog: listening on %s", addr)
	log.Fatal(httpSrv.ListenAndServe())
}

func (s *server) routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", health)
	mux.HandleFunc("GET /ready", s.ready)
	mux.HandleFunc("GET /products", s.listProducts)
	mux.HandleFunc("GET /products/{id}", s.getProduct)
}

func (s *server) listProducts(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.QueryContext(r.Context(),
		`SELECT id, sku, title, description, price_cents, image_url, stock
		   FROM products ORDER BY id`)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "query failed")
		log.Printf("catalog: list query: %v", err)
		return
	}
	defer rows.Close()

	out := make([]Product, 0, 16)
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
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)
	return db, nil
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
