package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/golang-jwt/jwt/v5"
	_ "github.com/lib/pq"
)

// maxBodyBytes caps createOrder's JSON body. Default net/http has no
// cap; an attacker sending a 100MB body under 20k concurrent pods
// OOMs the service. 64KiB is far above any legitimate order payload.
const maxBodyBytes = 64 << 10

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
		log.Printf("orders: listening on %s", addr)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("orders: server failed: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Printf("orders: shutdown signal received, draining for 20s")

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(ctx); err != nil {
		log.Printf("orders: shutdown error: %v", err)
	}
}

func recoverMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("orders: panic %v on %s %s", rec, r.Method, r.URL.Path)
				writeErr(w, http.StatusInternalServerError, "internal")
			}
		}()
		next.ServeHTTP(w, r)
	})
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

	// Cap request body + drain on close to prevent slowloris/OOM under
	// high fan-in. MaxBytesReader returns an error once maxBodyBytes
	// is exceeded; the drain+close keeps the TCP connection reusable.
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	defer func() {
		_, _ = io.Copy(io.Discard, r.Body)
		_ = r.Body.Close()
	}()

	var body struct {
		Items []orderItemInput `json:"items"`
	}
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&body); err != nil {
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

	// Single LEFT JOIN replaces the previous N+1 (1 query per order for
	// items). At 20k concurrent users × avg-orders-per-user, the old
	// path saturated the DB pool and triggered `503 db_unreachable`
	// cascades through auth's /ready probe.
	rows, err := s.db.QueryContext(r.Context(),
		`SELECT o.id, o.total_cents, o.status, o.created_at,
		        oi.product_id, oi.quantity, oi.price_cents
		   FROM orders o
		   LEFT JOIN order_items oi ON oi.order_id = o.id
		  WHERE o.user_id = $1
		  ORDER BY o.created_at DESC, o.id, oi.product_id`, userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "query failed")
		return
	}
	defer rows.Close()

	byID := make(map[int64]*order, 16)
	order_ids := make([]int64, 0, 16)
	for rows.Next() {
		var oID int64
		var total int
		var status string
		var createdAt time.Time
		var pid sql.NullInt64
		var qty, price sql.NullInt64

		if err := rows.Scan(&oID, &total, &status, &createdAt, &pid, &qty, &price); err != nil {
			writeErr(w, http.StatusInternalServerError, "scan failed")
			return
		}
		o, ok := byID[oID]
		if !ok {
			o = &order{
				ID: oID, UserID: userID, TotalCents: total,
				Status: status, CreatedAt: createdAt, Items: make([]orderItem, 0, 4),
			}
			byID[oID] = o
			order_ids = append(order_ids, oID)
		}
		if pid.Valid {
			o.Items = append(o.Items, orderItem{
				ProductID:  pid.Int64,
				Quantity:   int(qty.Int64),
				PriceCents: int(price.Int64),
			})
		}
	}
	if err := rows.Err(); err != nil {
		writeErr(w, http.StatusInternalServerError, "row iteration failed")
		return
	}

	out := make([]order, 0, len(order_ids))
	for _, id := range order_ids {
		out = append(out, *byID[id])
	}
	writeJSON(w, http.StatusOK, out)
}

// loadItems is retained for createOrder-path tests but no longer called
// from the hot path. Consider deleting when tests are refactored.
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
