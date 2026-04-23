package main

import (
	"context"
	"database/sql"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	_ "github.com/lib/pq"
)

// Service-wide configuration, sourced from env vars. Values come from
// k8s env (in prod) or docker-compose (locally).
type config struct {
	listenAddr         string
	jwtSecret          []byte
	accessTTL          time.Duration
	maxFailedAttempts  int
	lockoutDuration    time.Duration
	revocationReaperOn bool
}

// server bundles request-scoped dependencies — the DB handle, JWT
// signer, structured logger, and config knobs. Handlers hang off this
// struct so they're trivially unit-testable with a mock DB + secret.
type server struct {
	db     *sql.DB
	cfg    config
	logger *slog.Logger
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	cfg, err := loadConfig()
	if err != nil {
		logger.Error("config", "err", err)
		os.Exit(1)
	}

	db, err := openDB(buildDSN())
	if err != nil {
		logger.Error("db open", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	srv := &server{db: db, cfg: cfg, logger: logger}

	mux := http.NewServeMux()
	srv.routes(mux)
	mux.Handle("/metrics", metricsHandler())

	handler := chain(mux,
		recoverMiddleware(logger),
		requestIDMiddleware,
		loggingMiddleware(logger),
		securityHeadersMiddleware,
		metricsMiddleware,
	)

	httpSrv := &http.Server{
		Addr:         cfg.listenAddr,
		Handler:      handler,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	if cfg.revocationReaperOn {
		go srv.revocationReaper(context.Background())
	}

	go func() {
		logger.Info("listening", "addr", cfg.listenAddr, "access_ttl", cfg.accessTTL.String())
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	logger.Info("shutting down")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(ctx)
}

func (s *server) routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", health)
	mux.HandleFunc("GET /ready", s.ready)
	mux.HandleFunc("POST /signup", s.signup)
	mux.HandleFunc("POST /login", s.login)
	mux.Handle("POST /logout", s.requireAuth(http.HandlerFunc(s.logout)))
	mux.Handle("GET /me", s.requireAuth(http.HandlerFunc(s.me)))
}

func loadConfig() (config, error) {
	secret := os.Getenv("JWT_SIGNING_KEY")
	if secret == "" {
		return config{}, errMissingEnv("JWT_SIGNING_KEY")
	}

	return config{
		listenAddr:         envDefault("LISTEN_ADDR", "0.0.0.0:8080"),
		jwtSecret:          []byte(secret),
		accessTTL:          durationEnv("ACCESS_TOKEN_TTL", 2*time.Hour),
		maxFailedAttempts:  intEnv("MAX_FAILED_ATTEMPTS", 5),
		lockoutDuration:    durationEnv("LOCKOUT_DURATION", 15*time.Minute),
		revocationReaperOn: envDefault("REVOCATION_REAPER", "true") == "true",
	}, nil
}

func health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "healthy"})
}

func (s *server) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.db.PingContext(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "db_unreachable", "db unreachable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

// revocationReaper periodically purges revoked_tokens rows whose
// expires_at is already in the past — once the JWT would have expired
// anyway, tracking it is pointless.
func (s *server) revocationReaper(ctx context.Context) {
	t := time.NewTicker(15 * time.Minute)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			res, err := s.db.ExecContext(ctx, `DELETE FROM revoked_tokens WHERE expires_at < NOW()`)
			if err != nil {
				s.logger.Warn("revocation reaper", "err", err)
				continue
			}
			if n, _ := res.RowsAffected(); n > 0 {
				s.logger.Info("revocation reaper purged", "rows", n)
			}
		}
	}
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

func intEnv(k string, d int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return d
}

func durationEnv(k string, d time.Duration) time.Duration {
	if v := os.Getenv(k); v != "" {
		if parsed, err := time.ParseDuration(v); err == nil {
			return parsed
		}
	}
	return d
}

type envErr struct{ key string }

func (e envErr) Error() string  { return "missing required env: " + e.key }
func errMissingEnv(k string) error { return envErr{k} }
