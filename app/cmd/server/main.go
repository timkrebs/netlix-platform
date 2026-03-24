package main

import (
	"context"
	"crypto/tls"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/timkrebs/netlix-platform/app/internal/database"
	"github.com/timkrebs/netlix-platform/app/internal/handler"
)

func main() {
	db, err := database.Connect()
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer db.Close()

	if err := database.Migrate(db); err != nil {
		log.Fatalf("failed to run migrations: %v", err)
	}

	h := handler.New(db)
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", h.Healthz)
	mux.HandleFunc("/api/titles", h.ListTitles)
	mux.HandleFunc("/", h.Index)

	certPath := os.Getenv("TLS_CERT_PATH")
	keyPath := os.Getenv("TLS_KEY_PATH")

	var srv *http.Server

	if certPath != "" && keyPath != "" {
		tlsCert, err := tls.LoadX509KeyPair(certPath, keyPath)
		if err != nil {
			log.Fatalf("failed to load TLS cert: %v", err)
		}

		srv = &http.Server{
			Addr:    ":8443",
			Handler: mux,
			TLSConfig: &tls.Config{
				Certificates: []tls.Certificate{tlsCert},
				MinVersion:   tls.VersionTLS12,
			},
			ReadHeaderTimeout: 10 * time.Second,
		}

		log.Println("starting HTTPS server on :8443")
		go func() {
			if err := srv.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
				log.Fatalf("server error: %v", err)
			}
		}()
	} else {
		srv = &http.Server{
			Addr:              ":8080",
			Handler:           mux,
			ReadHeaderTimeout: 10 * time.Second,
		}

		log.Println("starting HTTP server on :8080 (no TLS certs found)")
		go func() {
			if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Fatalf("server error: %v", err)
			}
		}()
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("shutting down server...")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("server forced to shutdown: %v", err)
	}
	log.Println("server stopped")
}
