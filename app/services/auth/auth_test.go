package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"golang.org/x/crypto/bcrypt"
)

const testJWKSKid = "test"
const testJWKSKey = "test-secret-must-be-stable-for-tests"

// newTestJWKSManager writes a single-key JWKS document to a tempdir
// and returns a manager loaded from it. The key matches testJWKSKey
// so any helper that signs a JWT with that constant can be verified
// by srv.cfg.jwks.
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
	logger := slog.New(slog.NewTextHandler(discardWriter{}, nil))
	m, err := NewJWKSManager(path, logger)
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
	srv := &server{
		db: db,
		cfg: config{
			jwks:              newTestJWKSManager(t),
			accessTTL:         time.Hour,
			maxFailedAttempts: 3,
			lockoutDuration:   time.Minute,
		},
		logger: slog.New(slog.NewTextHandler(discardWriter{}, nil)),
	}
	return srv, mock, func() { db.Close() }
}

type discardWriter struct{}

func (discardWriter) Write(p []byte) (int, error) { return len(p), nil }

func jsonBody(v any) *bytes.Reader {
	b, _ := json.Marshal(v)
	return bytes.NewReader(b)
}

// ─── Validation ──────────────────────────────────────────────────────────

func TestValidateEmail(t *testing.T) {
	cases := map[string]bool{
		"":                           false,
		"not-an-email":               false,
		"a@b":                        false,
		"a@b.c":                      false,
		"alice@example.com":          true,
		"alice+tag@sub.example.com":  true,
		"UPPER@EXAMPLE.COM":          true,
	}
	for in, want := range cases {
		got := validateEmail(in) == nil
		if got != want {
			t.Errorf("validateEmail(%q) got ok=%v want %v", in, got, want)
		}
	}
}

func TestValidatePassword(t *testing.T) {
	cases := map[string]bool{
		"short":              false,
		"alllowercase":       false,
		"ALLUPPERCASEONLY":   false,
		"1234567890":         false,
		"Pass1!":             false, // 6 chars, too short
		"Password1!":         true,  // 10 chars, 4 classes
		"Password12!":        true,  // 11 chars, 4 classes
		"LongEnoughPass99":   true,  // upper+lower+digit
		"longenoughpass99!":  true,  // lower+digit+symbol
	}
	for in, want := range cases {
		got := validatePassword(in) == nil
		if got != want {
			t.Errorf("validatePassword(%q) got ok=%v want %v", in, got, want)
		}
	}
}

// ─── JWT + revocation ────────────────────────────────────────────────────

func TestIssueParseTokenRoundTrip(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	raw, exp, err := srv.issueToken(42, "alice@example.com")
	if err != nil {
		t.Fatalf("issueToken: %v", err)
	}
	if exp.Before(time.Now()) {
		t.Fatalf("expiry in past: %v", exp)
	}
	claims, err := srv.parseToken(raw)
	if err != nil {
		t.Fatalf("parseToken: %v", err)
	}
	if claims.UserID != 42 || claims.Email != "alice@example.com" || claims.JTI == "" {
		t.Fatalf("bad claims: %+v", claims)
	}
}

func TestParseTokenRejectsTampered(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()
	raw, _, _ := srv.issueToken(1, "a@b.c")
	if _, err := srv.parseToken(raw + "x"); err == nil {
		t.Fatal("expected parse failure on tampered token")
	}
}

// ─── Signup / Login ──────────────────────────────────────────────────────

func TestSignupSuccess(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	mock.ExpectQuery(`INSERT INTO users`).
		WithArgs("alice@example.com", sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at"}).AddRow(int64(42), time.Now()))

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodPost, "/signup",
		jsonBody(credentials{Email: "alice@example.com", Password: "GoodPass12!"}))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status: got %d want 201 body=%s", rec.Code, rec.Body.String())
	}
	var tr tokenResponse
	if err := json.NewDecoder(rec.Body).Decode(&tr); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if tr.UserID != 42 || tr.Email != "alice@example.com" || tr.Token == "" {
		t.Fatalf("unexpected response: %+v", tr)
	}
}

func TestSignupRejectsWeakPassword(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()
	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodPost, "/signup",
		jsonBody(credentials{Email: "a@b.co", Password: "weakpass"}))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d want 400", rec.Code)
	}
	var er errorResponse
	_ = json.NewDecoder(rec.Body).Decode(&er)
	if er.Error.Code != "weak_password" {
		t.Fatalf("expected code weak_password, got %s", er.Error.Code)
	}
}

func TestLoginSuccessResetsFailedAttempts(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	hash, _ := bcrypt.GenerateFromPassword([]byte("GoodPass12!"), bcrypt.MinCost)
	mock.ExpectQuery(`SELECT id, password_hash, failed_attempts, locked_until`).
		WithArgs("alice@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "password_hash", "failed_attempts", "locked_until"}).
			AddRow(int64(7), string(hash), 2, nil))
	mock.ExpectExec(`UPDATE users SET failed_attempts = 0, locked_until = NULL, last_login_at = NOW\(\)`).
		WithArgs(int64(7)).
		WillReturnResult(sqlmock.NewResult(0, 1))

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodPost, "/login",
		jsonBody(credentials{Email: "alice@example.com", Password: "GoodPass12!"}))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200 body=%s", rec.Code, rec.Body.String())
	}
}

func TestLoginLockoutAfterMaxFailedAttempts(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	hash, _ := bcrypt.GenerateFromPassword([]byte("RealPass12!"), bcrypt.MinCost)
	// User already at max-1 failures; this wrong attempt pushes them over.
	mock.ExpectQuery(`SELECT id, password_hash, failed_attempts, locked_until`).
		WithArgs("alice@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "password_hash", "failed_attempts", "locked_until"}).
			AddRow(int64(7), string(hash), 2, nil))
	mock.ExpectExec(`UPDATE users SET failed_attempts = \$1, locked_until = \$2`).
		WithArgs(3, sqlmock.AnyArg(), int64(7)).
		WillReturnResult(sqlmock.NewResult(0, 1))

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodPost, "/login",
		jsonBody(credentials{Email: "alice@example.com", Password: "WrongPass12!"}))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d want 401 body=%s", rec.Code, rec.Body.String())
	}
}

func TestLoginRejectedWhileLocked(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	hash, _ := bcrypt.GenerateFromPassword([]byte("GoodPass12!"), bcrypt.MinCost)
	future := time.Now().Add(5 * time.Minute)
	mock.ExpectQuery(`SELECT id, password_hash, failed_attempts, locked_until`).
		WithArgs("alice@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "password_hash", "failed_attempts", "locked_until"}).
			AddRow(int64(7), string(hash), 5, future))

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodPost, "/login",
		jsonBody(credentials{Email: "alice@example.com", Password: "GoodPass12!"}))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("status: got %d want 429 body=%s", rec.Code, rec.Body.String())
	}
}

// ─── Middleware: requireAuth + GET /me + POST /logout ────────────────────

func TestRequireAuthRejectsNoHeader(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()
	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d want 401", rec.Code)
	}
}

func TestMeSuccess(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	raw, _, _ := srv.issueToken(42, "alice@example.com")

	// revocation check → not revoked
	mock.ExpectQuery(`SELECT EXISTS`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))
	// profile lookup
	mock.ExpectQuery(`SELECT id, email, created_at, last_login_at`).
		WithArgs(int64(42)).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email", "created_at", "last_login_at"}).
			AddRow(int64(42), "alice@example.com", time.Now(), sql.NullTime{}))

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	req.Header.Set("Authorization", "Bearer "+raw)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200 body=%s", rec.Code, rec.Body.String())
	}
	var p userProfile
	_ = json.NewDecoder(rec.Body).Decode(&p)
	if p.ID != 42 || p.Email != "alice@example.com" {
		t.Fatalf("unexpected profile: %+v", p)
	}
}

func TestLogoutRevokesToken(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	raw, _, _ := srv.issueToken(42, "alice@example.com")

	// requireAuth revocation check
	mock.ExpectQuery(`SELECT EXISTS`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))
	// insert into revoked_tokens
	mock.ExpectExec(`INSERT INTO revoked_tokens`).
		WithArgs(sqlmock.AnyArg(), int64(42), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(0, 1))

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodPost, "/logout", nil)
	req.Header.Set("Authorization", "Bearer "+raw)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200 body=%s", rec.Code, rec.Body.String())
	}
}

func TestRequireAuthRejectsRevokedToken(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	raw, _, _ := srv.issueToken(42, "alice@example.com")
	mock.ExpectQuery(`SELECT EXISTS`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	req.Header.Set("Authorization", "Bearer "+raw)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d want 401", rec.Code)
	}
}
