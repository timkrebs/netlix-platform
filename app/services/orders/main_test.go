package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/golang-jwt/jwt/v5"
)

const testJWKSKid = "test"
const testJWKSKey = "test-secret"

// newTestJWKSManager writes a single-key JWKS document to a tempdir
// and returns a manager loaded from it. The key matches testJWKSKey
// so any helper that signs a JWT with that constant can be verified
// by srv.jwks.
func newTestJWKSManager(t *testing.T) *JWKSManager {
	t.Helper()
	doc := map[string]any{
		"primary_kid": testJWKSKid,
		"keys":        map[string]string{testJWKSKid: testJWKSKey},
	}
	body, err := json.Marshal(doc)
	if err != nil {
		t.Fatalf("marshal jwks: %v", err)
	}
	path := filepath.Join(t.TempDir(), "keys.json")
	if err := os.WriteFile(path, body, 0o644); err != nil {
		t.Fatalf("write jwks: %v", err)
	}
	m, err := NewJWKSManager(path)
	if err != nil {
		t.Fatalf("NewJWKSManager: %v", err)
	}
	return m
}

func newTestServer(t *testing.T) (*server, sqlmock.Sqlmock, func()) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	srv := &server{db: db, jwks: newTestJWKSManager(t)}
	return srv, mock, func() { db.Close() }
}

func makeToken(t *testing.T, secret []byte, userID int64) string {
	t.Helper()
	claims := jwt.MapClaims{
		"sub": userID,
		"jti": "test-jti-001",
		"exp": time.Now().Add(time.Hour).Unix(),
		"iat": time.Now().Unix(),
	}
	tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(secret)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return tok
}

// expectRevocationCheckNotRevoked stubs the SELECT EXISTS lookup that
// requireAuth performs after parsing the JWT.
func expectRevocationCheckNotRevoked(mock sqlmock.Sqlmock) {
	mock.ExpectQuery(`SELECT EXISTS`).
		WithArgs("test-jti-001").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))
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

	expectRevocationCheckNotRevoked(mock)
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
	req.Header.Set("Authorization", "Bearer "+makeToken(t, []byte(testJWKSKey), 7))
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

	expectRevocationCheckNotRevoked(mock)
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
	req.Header.Set("Authorization", "Bearer "+makeToken(t, []byte(testJWKSKey), 7))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("status: got %d want 409, body=%s", rec.Code, rec.Body.String())
	}
}

func TestRequireAuthRejectsRevokedToken(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	mock.ExpectQuery(`SELECT EXISTS`).
		WithArgs("test-jti-001").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodGet, "/orders", nil)
	req.Header.Set("Authorization", "Bearer "+makeToken(t, []byte(testJWKSKey), 7))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d want 401, body=%s", rec.Code, rec.Body.String())
	}
}
