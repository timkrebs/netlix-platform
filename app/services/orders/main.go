package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	_ "github.com/lib/pq"
)

type orderItemInput struct {
	ProductID int64 `json:"product_id"`
	Quantity  int   `json:"quantity"`
}

type orderItem struct {
	ProductID  int64 `json:"product_id"`
	Quantity   int   `json:"quantity"`
	PriceCents int   `json:"price_cents"`
}

type order struct {
	ID         int64       `json:"id"`
	UserID     int64       `json:"user_id"`
	TotalCents int         `json:"total_cents"`
	Status     string      `json:"status"`
	CreatedAt  time.Time   `json:"created_at"`
	Items      []orderItem `json:"items"`
}

type ctxKey string

const userIDKey ctxKey = "user_id"

type server struct {
	db        *sql.DB
	jwtSecret []byte
}

func main() {
	secret := os.Getenv("JWT_SIGNING_KEY")
	if secret == "" {
		log.Fatal("orders: JWT_SIGNING_KEY is required")
	}

	db, err := openDB(buildDSN())
	if err != nil {
		log.Fatalf("orders: db open: %v", err)
	}
	defer db.Close()

	srv := &server{db: db, jwtSecret: []byte(secret)}

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

	log.Printf("orders: listening on %s", addr)
	log.Fatal(httpSrv.ListenAndServe())
}

func (s *server) routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", health)
	mux.HandleFunc("GET /ready", s.ready)
	mux.Handle("POST /orders", s.requireAuth(http.HandlerFunc(s.createOrder)))
	mux.Handle("GET /orders", s.requireAuth(http.HandlerFunc(s.listOrders)))
}

func (s *server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			writeErr(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		raw := strings.TrimPrefix(auth, "Bearer ")
		uid, jti, err := s.parseToken(raw)
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "invalid token")
			return
		}
		revoked, err := s.isTokenRevoked(r.Context(), jti)
		if err != nil {
			log.Printf("orders: revocation check: %v", err)
			writeErr(w, http.StatusInternalServerError, "auth check failed")
			return
		}
		if revoked {
			writeErr(w, http.StatusUnauthorized, "token has been revoked")
			return
		}
		ctx := context.WithValue(r.Context(), userIDKey, uid)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *server) parseToken(raw string) (int64, string, error) {
	t, err := jwt.Parse(raw, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return s.jwtSecret, nil
	})
	if err != nil || !t.Valid {
		return 0, "", fmt.Errorf("invalid token")
	}
	claims, ok := t.Claims.(jwt.MapClaims)
	if !ok {
		return 0, "", fmt.Errorf("invalid claims")
	}
	sub, ok := claims["sub"].(float64)
	if !ok {
		return 0, "", fmt.Errorf("invalid sub claim")
	}
	jti, _ := claims["jti"].(string)
	return int64(sub), jti, nil
}

// isTokenRevoked checks the shared revoked_tokens table. Auth-issued
// tokens older than this service's deploy may not have a jti (legacy);
// in that case we fall back to accepting them — fixed by the next
// login cycle.
func (s *server) isTokenRevoked(ctx context.Context, jti string) (bool, error) {
	if jti == "" {
		return false, nil
	}
	var exists bool
	err := s.db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM revoked_tokens WHERE jti = $1)`, jti).Scan(&exists)
	return exists, err
}

func (s *server) createOrder(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value(userIDKey).(int64)

	var body struct {
		Items []orderItemInput `json:"items"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid body")
		return
	}
	if len(body.Items) == 0 {
		writeErr(w, http.StatusBadRequest, "order must contain at least one item")
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "tx begin failed")
		return
	}
	defer tx.Rollback()

	total := 0
	priced := make([]orderItem, 0, len(body.Items))
	for _, it := range body.Items {
		if it.Quantity <= 0 {
			writeErr(w, http.StatusBadRequest, "quantity must be > 0")
			return
		}
		var price, stock int
		err := tx.QueryRowContext(r.Context(),
			`SELECT price_cents, stock FROM products WHERE id = $1 FOR UPDATE`, it.ProductID).
			Scan(&price, &stock)
		if errors.Is(err, sql.ErrNoRows) {
			writeErr(w, http.StatusBadRequest, fmt.Sprintf("product %d not found", it.ProductID))
			return
		}
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "lookup failed")
			return
		}
		if stock < it.Quantity {
			writeErr(w, http.StatusConflict, fmt.Sprintf("insufficient stock for product %d", it.ProductID))
			return
		}
		if _, err := tx.ExecContext(r.Context(),
			`UPDATE products SET stock = stock - $1 WHERE id = $2`, it.Quantity, it.ProductID); err != nil {
			writeErr(w, http.StatusInternalServerError, "stock update failed")
			return
		}
		total += price * it.Quantity
		priced = append(priced, orderItem{ProductID: it.ProductID, Quantity: it.Quantity, PriceCents: price})
	}

	var orderID int64
	var createdAt time.Time
	err = tx.QueryRowContext(r.Context(),
		`INSERT INTO orders (user_id, total_cents, status) VALUES ($1, $2, 'confirmed')
		   RETURNING id, created_at`,
		userID, total).Scan(&orderID, &createdAt)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "order insert failed")
		return
	}

	for _, it := range priced {
		if _, err := tx.ExecContext(r.Context(),
			`INSERT INTO order_items (order_id, product_id, quantity, price_cents)
			   VALUES ($1, $2, $3, $4)`,
			orderID, it.ProductID, it.Quantity, it.PriceCents); err != nil {
			writeErr(w, http.StatusInternalServerError, "item insert failed")
			return
		}
	}

	if err := tx.Commit(); err != nil {
		writeErr(w, http.StatusInternalServerError, "commit failed")
		return
	}

	writeJSON(w, http.StatusCreated, order{
		ID: orderID, UserID: userID, TotalCents: total,
		Status: "confirmed", CreatedAt: createdAt, Items: priced,
	})
}

func (s *server) listOrders(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value(userIDKey).(int64)

	rows, err := s.db.QueryContext(r.Context(),
		`SELECT id, total_cents, status, created_at FROM orders
		   WHERE user_id = $1 ORDER BY created_at DESC`, userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "query failed")
		return
	}
	defer rows.Close()

	out := make([]order, 0, 8)
	for rows.Next() {
		o := order{UserID: userID}
		if err := rows.Scan(&o.ID, &o.TotalCents, &o.Status, &o.CreatedAt); err != nil {
			writeErr(w, http.StatusInternalServerError, "scan failed")
			return
		}
		out = append(out, o)
	}
	for i := range out {
		items, err := s.loadItems(r.Context(), out[i].ID)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "item load failed")
			return
		}
		out[i].Items = items
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *server) loadItems(ctx context.Context, orderID int64) ([]orderItem, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT product_id, quantity, price_cents FROM order_items WHERE order_id = $1`, orderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]orderItem, 0, 4)
	for rows.Next() {
		var it orderItem
		if err := rows.Scan(&it.ProductID, &it.Quantity, &it.PriceCents); err != nil {
			return nil, err
		}
		items = append(items, it)
	}
	return items, nil
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
