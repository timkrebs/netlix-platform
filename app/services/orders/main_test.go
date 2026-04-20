package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/golang-jwt/jwt/v5"
)

func newTestServer(t *testing.T) (*server, sqlmock.Sqlmock, func()) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	srv := &server{db: db, jwtSecret: []byte("test-secret")}
	return srv, mock, func() { db.Close() }
}

func makeToken(t *testing.T, secret []byte, userID int64) string {
	t.Helper()
	claims := jwt.MapClaims{
		"sub": userID,
		"exp": time.Now().Add(time.Hour).Unix(),
		"iat": time.Now().Unix(),
	}
	tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(secret)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return tok
}

func TestRequireAuthRejectsMissingHeader(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()
	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodGet, "/orders", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d want 401", rec.Code)
	}
}

func TestRequireAuthRejectsBadToken(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()
	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodGet, "/orders", nil)
	req.Header.Set("Authorization", "Bearer not-a-real-jwt")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d want 401", rec.Code)
	}
}

func TestCreateOrderHappyPath(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT price_cents, stock FROM products").
		WithArgs(int64(1)).
		WillReturnRows(sqlmock.NewRows([]string{"price_cents", "stock"}).AddRow(2499, 10))
	mock.ExpectExec("UPDATE products SET stock").
		WithArgs(2, int64(1)).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("INSERT INTO orders").
		WithArgs(int64(7), 4998).
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at"}).AddRow(int64(99), time.Now()))
	mock.ExpectExec("INSERT INTO order_items").
		WithArgs(int64(99), int64(1), 2, 2499).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	mux := http.NewServeMux()
	srv.routes(mux)

	body, _ := json.Marshal(map[string]any{
		"items": []map[string]int{{"product_id": 1, "quantity": 2}},
	})
	req := httptest.NewRequest(http.MethodPost, "/orders", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+makeToken(t, srv.jwtSecret, 7))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status: got %d want 201, body=%s", rec.Code, rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

func TestCreateOrderInsufficientStock(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT price_cents, stock FROM products").
		WithArgs(int64(1)).
		WillReturnRows(sqlmock.NewRows([]string{"price_cents", "stock"}).AddRow(2499, 1))
	mock.ExpectRollback()

	mux := http.NewServeMux()
	srv.routes(mux)

	body, _ := json.Marshal(map[string]any{
		"items": []map[string]int{{"product_id": 1, "quantity": 5}},
	})
	req := httptest.NewRequest(http.MethodPost, "/orders", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+makeToken(t, srv.jwtSecret, 7))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("status: got %d want 409, body=%s", rec.Code, rec.Body.String())
	}
}
