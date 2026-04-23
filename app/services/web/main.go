package main

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

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
		Addr:         listenAddr,
		Handler:      metricsMiddleware(mux),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  30 * time.Second,
	}

	useTLS := fileExists(tlsCert) && fileExists(tlsKey)

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
		log.Fatal(server.ListenAndServeTLS("", ""))
	} else {
		log.Printf("Starting %s (HTTP) on %s [env=%s, version=%s]", name, listenAddr, environment, version)
		log.Fatal(server.ListenAndServe())
	}
}

func callUpstream(uri string) *UpstreamResponse {
	start := time.Now()
	client := &http.Client{Timeout: 5 * time.Second}

	resp, err := client.Get(uri)
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
