package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	_ "github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"
)

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type tokenResponse struct {
	Token  string `json:"token"`
	UserID int64  `json:"user_id"`
	Email  string `json:"email"`
}

type server struct {
	db        *sql.DB
	jwtSecret []byte
	jwtTTL    time.Duration
}

func main() {
	secret := os.Getenv("JWT_SIGNING_KEY")
	if secret == "" {
		log.Fatal("auth: JWT_SIGNING_KEY is required")
	}

	db, err := openDB(buildDSN())
	if err != nil {
		log.Fatalf("auth: db open: %v", err)
	}
	defer db.Close()

	srv := &server{
		db:        db,
		jwtSecret: []byte(secret),
		jwtTTL:    24 * time.Hour,
	}

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

	log.Printf("auth: listening on %s", addr)
	log.Fatal(httpSrv.ListenAndServe())
}

func (s *server) routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", health)
	mux.HandleFunc("GET /ready", s.ready)
	mux.HandleFunc("POST /signup", s.signup)
	mux.HandleFunc("POST /login", s.login)
}

func (s *server) signup(w http.ResponseWriter, r *http.Request) {
	var c credentials
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid body")
		return
	}
	c.Email = strings.TrimSpace(strings.ToLower(c.Email))
	if c.Email == "" || len(c.Password) < 8 {
		writeErr(w, http.StatusBadRequest, "email required and password must be 8+ chars")
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(c.Password), bcrypt.DefaultCost)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "hash failed")
		return
	}

	var id int64
	err = s.db.QueryRowContext(r.Context(),
		`INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id`,
		c.Email, string(hash)).Scan(&id)
	if err != nil {
		if isUniqueViolation(err) {
			writeErr(w, http.StatusConflict, "email already registered")
			return
		}
		writeErr(w, http.StatusInternalServerError, "insert failed")
		log.Printf("auth: signup insert: %v", err)
		return
	}

	tok, err := s.issueToken(id, c.Email)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "token issue failed")
		return
	}
	writeJSON(w, http.StatusCreated, tokenResponse{Token: tok, UserID: id, Email: c.Email})
}

func (s *server) login(w http.ResponseWriter, r *http.Request) {
	var c credentials
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid body")
		return
	}
	c.Email = strings.TrimSpace(strings.ToLower(c.Email))

	var (
		id   int64
		hash string
	)
	err := s.db.QueryRowContext(r.Context(),
		`SELECT id, password_hash FROM users WHERE email = $1`, c.Email).
		Scan(&id, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "query failed")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(c.Password)); err != nil {
		writeErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	tok, err := s.issueToken(id, c.Email)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "token issue failed")
		return
	}
	writeJSON(w, http.StatusOK, tokenResponse{Token: tok, UserID: id, Email: c.Email})
}

func (s *server) issueToken(userID int64, email string) (string, error) {
	claims := jwt.MapClaims{
		"sub":   userID,
		"email": email,
		"iat":   time.Now().Unix(),
		"exp":   time.Now().Add(s.jwtTTL).Unix(),
		"iss":   "netlix-auth",
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return t.SignedString(s.jwtSecret)
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

// isUniqueViolation reports whether err is a Postgres unique-constraint
// violation (SQLSTATE 23505). Avoids importing pgx just for the error code.
func isUniqueViolation(err error) bool {
	return err != nil && strings.Contains(err.Error(), "duplicate key value")
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}
