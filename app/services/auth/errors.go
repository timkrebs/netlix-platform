package main

import (
	"encoding/json"
	"net/http"
)

// errorResponse is the canonical error format returned by every endpoint.
// `code` is a stable machine-friendly identifier that the SPA branches on;
// `message` is human-readable and safe to render directly in UI.
type errorResponse struct {
	Error errorBody `json:"error"`
}

type errorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, errorResponse{Error: errorBody{Code: code, Message: msg}})
}
