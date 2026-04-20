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
	"golang.org/x/crypto/bcrypt"
)

func newTestServer(t *testing.T) (*server, sqlmock.Sqlmock, func()) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	srv := &server{db: db, jwtSecret: []byte("test-secret"), jwtTTL: time.Hour}
	return srv, mock, func() { db.Close() }
}

func TestSignupAndIssueToken(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	mock.ExpectQuery("INSERT INTO users").
		WithArgs("alice@example.com", sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(int64(42)))

	mux := http.NewServeMux()
	srv.routes(mux)

	body, _ := json.Marshal(map[string]string{"email": "alice@example.com", "password": "supersecret"})
	req := httptest.NewRequest(http.MethodPost, "/signup", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status: got %d want 201, body=%s", rec.Code, rec.Body.String())
	}
	var resp tokenResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.UserID != 42 || resp.Email != "alice@example.com" || resp.Token == "" {
		t.Fatalf("unexpected response: %+v", resp)
	}

	// Token should parse and validate.
	tok, err := jwt.Parse(resp.Token, func(_ *jwt.Token) (any, error) { return srv.jwtSecret, nil })
	if err != nil || !tok.Valid {
		t.Fatalf("token invalid: %v", err)
	}
}

func TestSignupShortPassword(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()
	mux := http.NewServeMux()
	srv.routes(mux)

	body, _ := json.Marshal(map[string]string{"email": "x@y.z", "password": "short"})
	req := httptest.NewRequest(http.MethodPost, "/signup", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d want 400", rec.Code)
	}
}

func TestLoginSuccess(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	hash, _ := bcrypt.GenerateFromPassword([]byte("supersecret"), bcrypt.MinCost)
	mock.ExpectQuery("SELECT id, password_hash FROM users").
		WithArgs("alice@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "password_hash"}).AddRow(int64(7), string(hash)))

	mux := http.NewServeMux()
	srv.routes(mux)

	body, _ := json.Marshal(map[string]string{"email": "alice@example.com", "password": "supersecret"})
	req := httptest.NewRequest(http.MethodPost, "/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200, body=%s", rec.Code, rec.Body.String())
	}
}

func TestLoginWrongPassword(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	hash, _ := bcrypt.GenerateFromPassword([]byte("realpassword"), bcrypt.MinCost)
	mock.ExpectQuery("SELECT id, password_hash FROM users").
		WithArgs("alice@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "password_hash"}).AddRow(int64(7), string(hash)))

	mux := http.NewServeMux()
	srv.routes(mux)

	body, _ := json.Marshal(map[string]string{"email": "alice@example.com", "password": "wrongpassword"})
	req := httptest.NewRequest(http.MethodPost, "/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d want 401", rec.Code)
	}
}
