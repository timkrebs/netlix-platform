package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"runtime/debug"
	"strings"
	"time"
)

type ctxKey string

const (
	requestIDKey ctxKey = "request_id"
	claimsKey    ctxKey = "claims"
)

func chain(h http.Handler, middlewares ...func(http.Handler) http.Handler) http.Handler {
	for i := len(middlewares) - 1; i >= 0; i-- {
		h = middlewares[i](h)
	}
	return h
}

func requestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if id == "" {
			b := make([]byte, 8)
			_, _ = rand.Read(b)
			id = hex.EncodeToString(b)
		}
		w.Header().Set("X-Request-ID", id)
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), requestIDKey, id)))
	})
}

// statusRecorder lets logging middleware report the response status.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (sr *statusRecorder) WriteHeader(s int) {
	sr.status = s
	sr.ResponseWriter.WriteHeader(s)
}

func loggingMiddleware(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			sr := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(sr, r)
			logger.Info("request",
				"method", r.Method,
				"path", r.URL.Path,
				"status", sr.status,
				"dur_ms", time.Since(start).Milliseconds(),
				"req_id", r.Context().Value(requestIDKey),
			)
		})
	}
}

func recoverMiddleware(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if rec := recover(); rec != nil {
					logger.Error("panic recovered",
						"err", rec,
						"path", r.URL.Path,
						"stack", string(debug.Stack()),
					)
					writeError(w, http.StatusInternalServerError, "internal", "internal server error")
				}
			}()
			next.ServeHTTP(w, r)
		})
	}
}

// securityHeadersMiddleware sets a conservative baseline. Most matter
// only when a browser is the client (i.e. the SPA), but they're cheap
// to send for API responses too.
func securityHeadersMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		next.ServeHTTP(w, r)
	})
}

// requireAuth gates handlers behind a Bearer token. It validates the
// JWT, checks the revocation list, and stuffs the claims into the
// request context for handlers to read.
func (s *server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			writeError(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
			return
		}
		raw := strings.TrimPrefix(auth, "Bearer ")
		claims, err := s.parseToken(raw)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "invalid_token", "token is invalid or expired")
			return
		}
		revoked, err := s.isRevoked(r.Context(), claims.JTI)
		if err != nil {
			s.logger.Error("revocation check", "err", err)
			writeError(w, http.StatusInternalServerError, "internal", "auth check failed")
			return
		}
		if revoked {
			writeError(w, http.StatusUnauthorized, "token_revoked", "token has been revoked")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), claimsKey, claims)))
	})
}

func claimsFromCtx(ctx context.Context) *tokenClaims {
	v, _ := ctx.Value(claimsKey).(*tokenClaims)
	return v
}
