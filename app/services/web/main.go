package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

// Shared HTTP client for upstream calls. The previous implementation
// allocated a fresh http.Client per request (one per incoming request
// → one per upstream call) which meant no connection reuse, TLS
// handshakes on every call, and accumulating goroutines under load.
var upstreamClient = &http.Client{
	Timeout: 5 * time.Second,
	Transport: &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   3 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		MaxIdleConns:          100,
		MaxIdleConnsPerHost:   16,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   3 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		ForceAttemptHTTP2:     true,
	},
}

type Response struct {
	Name        string            `json:"name"`
	Message     string            `json:"message"`
	Environment string            `json:"environment"`
	Version     string            `json:"version"`
	Hostname    string            `json:"hostname"`
	TLS         bool              `json:"tls"`
	Timestamp   string            `json:"timestamp"`
	Upstream    *UpstreamResponse `json:"upstream,omitempty"`
}

type UpstreamResponse struct {
	URI      string `json:"uri"`
	Status   int    `json:"status"`
	Body     string `json:"body"`
	Duration string `json:"duration"`
}

func main() {
	name := getEnv("NAME", "web")
	message := getEnv("MESSAGE", "Hello from the web frontend")
	listenAddr := getEnv("LISTEN_ADDR", "0.0.0.0:8080")
	upstreamURIs := getEnv("UPSTREAM_URIS", "")
	environment := getEnv("ENVIRONMENT", "dev")
	version := getEnv("VERSION", "unknown")

	tlsCert := getEnv("TLS_CERT_PATH", "/vault/secrets/tls.crt")
	tlsKey := getEnv("TLS_KEY_PATH", "/vault/secrets/tls.key")

	hostname, _ := os.Hostname()

	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}

		resp := Response{
			Name:        name,
			Message:     message,
			Environment: environment,
			Version:     version,
			Hostname:    hostname,
			Timestamp:   time.Now().UTC().Format(time.RFC3339),
		}

		if _, err := os.Stat(tlsCert); err == nil {
			resp.TLS = true
		}

		if upstreamURIs != "" {
			for _, uri := range strings.Split(upstreamURIs, ",") {
				uri = strings.TrimSpace(uri)
				upstream := callUpstream(uri)
				resp.Upstream = upstream
				break // only use the first upstream for simplicity
			}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
	})

	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
	})

	mux.Handle("/metrics", metricsHandler())

	server := &http.Server{
		Addr:              listenAddr,
		Handler:           recoverMiddleware(metricsMiddleware(mux)),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       30 * time.Second,
	}

	useTLS := fileExists(tlsCert) && fileExists(tlsKey)

	go func() {
		if useTLS {
			log.Printf("Starting %s (TLS) on %s [env=%s, version=%s]", name, listenAddr, environment, version)
			cert, err := tls.LoadX509KeyPair(tlsCert, tlsKey)
			if err != nil {
				log.Fatalf("Failed to load TLS cert: %v", err)
			}
			server.TLSConfig = &tls.Config{
				Certificates: []tls.Certificate{cert},
				MinVersion:   tls.VersionTLS12,
			}
			if err := server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
				log.Fatalf("web: server (TLS) failed: %v", err)
			}
		} else {
			log.Printf("Starting %s (HTTP) on %s [env=%s, version=%s]", name, listenAddr, environment, version)
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Fatalf("web: server failed: %v", err)
			}
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Printf("web: shutdown signal received, draining for 10s")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		log.Printf("web: shutdown error: %v", err)
	}
}

func recoverMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("web: panic %v on %s %s", rec, r.Method, r.URL.Path)
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusInternalServerError)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "internal"})
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func callUpstream(uri string) *UpstreamResponse {
	start := time.Now()
	resp, err := upstreamClient.Get(uri)
	if err != nil {
		return &UpstreamResponse{
			URI:      uri,
			Status:   0,
			Body:     fmt.Sprintf("error: %v", err),
			Duration: time.Since(start).String(),
		}
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))

	return &UpstreamResponse{
		URI:      uri,
		Status:   resp.StatusCode,
		Body:     string(body),
		Duration: time.Since(start).String(),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
