package main

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	httpRequests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total HTTP requests by method, path, status.",
	}, []string{"method", "path", "status"})

	httpDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request latency in seconds.",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "path"})
)

func metricsHandler() http.Handler { return promhttp.Handler() }

type metricsRecorder struct {
	http.ResponseWriter
	status int
}

func (m *metricsRecorder) WriteHeader(s int) {
	m.status = s
	m.ResponseWriter.WriteHeader(s)
}

func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}
		start := time.Now()
		rec := &metricsRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		// Label paths by the API prefix so cardinality stays bounded
		// (gateway proxies arbitrary paths — `/api/orders/42` would
		// blow up the label set if recorded verbatim).
		path := normalizeGatewayPath(r.URL.Path)
		httpRequests.WithLabelValues(r.Method, path, strconv.Itoa(rec.status)).Inc()
		httpDuration.WithLabelValues(r.Method, path).Observe(time.Since(start).Seconds())
	})
}

func normalizeGatewayPath(p string) string {
	switch {
	case p == "/health", p == "/ready", p == "/metrics":
		return p
	case len(p) >= 13 && p[:13] == "/api/catalog/":
		return "/api/catalog"
	case len(p) >= 10 && p[:10] == "/api/auth/":
		return "/api/auth"
	case len(p) >= 12 && p[:12] == "/api/orders/":
		return "/api/orders"
	default:
		return "/spa"
	}
}
