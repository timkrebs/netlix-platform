package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
)

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type tokenResponse struct {
	Token     string    `json:"token"`
	UserID    int64     `json:"user_id"`
	Email     string    `json:"email"`
	ExpiresAt time.Time `json:"expires_at"`
}

type userProfile struct {
	ID          int64      `json:"id"`
	Email       string     `json:"email"`
	CreatedAt   time.Time  `json:"created_at"`
	LastLoginAt *time.Time `json:"last_login_at,omitempty"`
}

func (s *server) signup(w http.ResponseWriter, r *http.Request) {
	var c credentials
	if err := decodeJSON(r, &c); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_body", "request body must be valid JSON")
		return
	}
	c.Email = strings.TrimSpace(strings.ToLower(c.Email))

	if err := validateEmail(c.Email); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_email", err.Error())
		return
	}
	if err := validatePassword(c.Password); err != nil {
		writeError(w, http.StatusBadRequest, "weak_password", err.Error())
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(c.Password), bcrypt.DefaultCost)
	if err != nil {
		s.logger.Error("bcrypt", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "failed to create account")
		return
	}

	var id int64
	var createdAt time.Time
	err = s.db.QueryRowContext(r.Context(),
		`INSERT INTO users (email, password_hash)
		 VALUES ($1, $2)
		 RETURNING id, created_at`,
		c.Email, string(hash)).Scan(&id, &createdAt)
	if err != nil {
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "email_taken", "email already registered")
			return
		}
		s.logger.Error("signup insert", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "failed to create account")
		return
	}

	tok, exp, err := s.issueToken(id, c.Email)
	if err != nil {
		s.logger.Error("issue token", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "failed to issue token")
		return
	}
	s.logger.Info("signup", "user_id", id, "email", c.Email)
	writeJSON(w, http.StatusCreated, tokenResponse{Token: tok, UserID: id, Email: c.Email, ExpiresAt: exp})
}

func (s *server) login(w http.ResponseWriter, r *http.Request) {
	var c credentials
	if err := decodeJSON(r, &c); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_body", "request body must be valid JSON")
		return
	}
	c.Email = strings.TrimSpace(strings.ToLower(c.Email))

	var (
		id              int64
		hash            string
		failedAttempts  int
		lockedUntil     sql.NullTime
	)
	err := s.db.QueryRowContext(r.Context(),
		`SELECT id, password_hash, failed_attempts, locked_until
		 FROM users WHERE email = $1`, c.Email).
		Scan(&id, &hash, &failedAttempts, &lockedUntil)
	if errors.Is(err, sql.ErrNoRows) {
		// Constant-time response to not leak email existence.
		_ = bcrypt.CompareHashAndPassword([]byte("$2a$10$abcdefghijklmnopqrstuu"), []byte(c.Password))
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
		return
	}
	if err != nil {
		s.logger.Error("login query", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "failed to authenticate")
		return
	}

	if lockedUntil.Valid && lockedUntil.Time.After(time.Now()) {
		writeError(w, http.StatusTooManyRequests, "account_locked",
			"account temporarily locked due to too many failed attempts")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(c.Password)); err != nil {
		s.recordFailedLogin(r, id, failedAttempts)
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
		return
	}

	// Success — reset counters + stamp last_login_at.
	if _, err := s.db.ExecContext(r.Context(),
		`UPDATE users SET failed_attempts = 0, locked_until = NULL, last_login_at = NOW()
		 WHERE id = $1`, id); err != nil {
		s.logger.Warn("update login stamps", "err", err)
	}

	tok, exp, err := s.issueToken(id, c.Email)
	if err != nil {
		s.logger.Error("issue token", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "failed to issue token")
		return
	}
	s.logger.Info("login", "user_id", id, "email", c.Email)
	writeJSON(w, http.StatusOK, tokenResponse{Token: tok, UserID: id, Email: c.Email, ExpiresAt: exp})
}

func (s *server) recordFailedLogin(r *http.Request, userID int64, current int) {
	newCount := current + 1
	var lockedUntil interface{} = nil
	if newCount >= s.cfg.maxFailedAttempts {
		lockedUntil = time.Now().Add(s.cfg.lockoutDuration)
		s.logger.Warn("account locked", "user_id", userID, "until", lockedUntil)
	}
	if _, err := s.db.ExecContext(r.Context(),
		`UPDATE users SET failed_attempts = $1, locked_until = $2 WHERE id = $3`,
		newCount, lockedUntil, userID); err != nil {
		s.logger.Warn("record failed login", "err", err)
	}
}

func (s *server) logout(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromCtx(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized", "not authenticated")
		return
	}
	if _, err := s.db.ExecContext(r.Context(),
		`INSERT INTO revoked_tokens (jti, user_id, expires_at)
		 VALUES ($1, $2, to_timestamp($3))
		 ON CONFLICT (jti) DO NOTHING`,
		claims.JTI, claims.UserID, claims.ExpiresUnix); err != nil {
		s.logger.Error("revoke token", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "failed to log out")
		return
	}
	s.logger.Info("logout", "user_id", claims.UserID, "jti", claims.JTI)
	writeJSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func (s *server) me(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromCtx(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized", "not authenticated")
		return
	}
	var p userProfile
	var lastLogin sql.NullTime
	err := s.db.QueryRowContext(r.Context(),
		`SELECT id, email, created_at, last_login_at FROM users WHERE id = $1`, claims.UserID).
		Scan(&p.ID, &p.Email, &p.CreatedAt, &lastLogin)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusUnauthorized, "unauthorized", "user no longer exists")
		return
	}
	if err != nil {
		s.logger.Error("me query", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "failed to load profile")
		return
	}
	if lastLogin.Valid {
		p.LastLoginAt = &lastLogin.Time
	}
	writeJSON(w, http.StatusOK, p)
}

func decodeJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

// isUniqueViolation reports whether err is a Postgres unique-constraint
// violation (SQLSTATE 23505).
func isUniqueViolation(err error) bool {
	return err != nil && strings.Contains(err.Error(), "duplicate key value")
}
