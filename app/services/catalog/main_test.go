package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func newTestServer(t *testing.T) (*server, sqlmock.Sqlmock, func()) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	return &server{db: db}, mock, func() { db.Close() }
}

func TestListProducts(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	rows := sqlmock.NewRows([]string{"id", "sku", "title", "description", "price_cents", "image_url", "stock"}).
		AddRow(1, "SKU-1", "Tee", "Cotton tee", 1999, "/img/t.png", 10).
		AddRow(2, "SKU-2", "Cap", "Dad cap", 1299, "/img/c.png", 5)
	mock.ExpectQuery("SELECT id, sku, title").WillReturnRows(rows)

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodGet, "/products", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200", rec.Code)
	}
	var got []Product
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got) != 2 || got[0].SKU != "SKU-1" || got[1].PriceCents != 1299 {
		t.Fatalf("unexpected payload: %+v", got)
	}
}

func TestGetProductNotFound(t *testing.T) {
	srv, mock, cleanup := newTestServer(t)
	defer cleanup()

	mock.ExpectQuery("SELECT id, sku, title").
		WithArgs(int64(99)).
		WillReturnRows(sqlmock.NewRows([]string{"id", "sku", "title", "description", "price_cents", "image_url", "stock"}))

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodGet, "/products/99", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d want 404", rec.Code)
	}
}

func TestGetProductInvalidID(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	mux := http.NewServeMux()
	srv.routes(mux)

	req := httptest.NewRequest(http.MethodGet, "/products/abc", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d want 400", rec.Code)
	}
}

func TestHealth(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", health)
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200", rec.Code)
	}
}
