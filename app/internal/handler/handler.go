package handler

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
)

type Handler struct {
	db *sql.DB
}

func New(db *sql.DB) *Handler {
	return &Handler{db: db}
}

type Title struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Genre string `json:"genre"`
	Year  int    `json:"year"`
}

func (h *Handler) Healthz(w http.ResponseWriter, r *http.Request) {
	if err := h.db.Ping(); err != nil {
		http.Error(w, "database unreachable", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (h *Handler) ListTitles(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.Query("SELECT id, name, genre, year FROM titles ORDER BY id")
	if err != nil {
		log.Printf("query error: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var titles []Title
	for rows.Next() {
		var t Title
		if err := rows.Scan(&t.ID, &t.Name, &t.Genre, &t.Year); err != nil {
			log.Printf("scan error: %v", err)
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		titles = append(titles, t)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(titles)
}

func (h *Handler) Index(w http.ResponseWriter, r *http.Request) {
	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "dev"
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(`<!DOCTYPE html>
<html>
<head>
    <title>Netlix</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #141414; color: #fff; }
        header { background: linear-gradient(to bottom, rgba(0,0,0,0.7), #141414); padding: 2rem; }
        h1 { font-size: 3rem; color: #e50914; font-weight: 900; letter-spacing: -0.05em; }
        .subtitle { color: #999; margin-top: 0.5rem; }
        .content { padding: 2rem; }
        .badge { display: inline-block; background: #e50914; color: #fff; padding: 0.25rem 0.75rem; border-radius: 4px; font-size: 0.85rem; margin-bottom: 1rem; }
        .info { background: #1f1f1f; border-radius: 8px; padding: 1.5rem; margin-top: 1rem; }
        .info h3 { color: #e50914; margin-bottom: 0.75rem; }
        .info p { color: #aaa; line-height: 1.6; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; margin-top: 1.5rem; }
        .card { background: #1f1f1f; border-radius: 8px; padding: 1rem; transition: transform 0.2s; }
        .card:hover { transform: scale(1.05); }
        .card h4 { color: #fff; margin-bottom: 0.25rem; }
        .card .genre { color: #e50914; font-size: 0.85rem; }
        .card .year { color: #666; font-size: 0.85rem; }
        #titles { min-height: 100px; }
        .version { color: #444; font-size: 0.75rem; position: fixed; bottom: 1rem; right: 1rem; }
    </style>
</head>
<body>
    <header>
        <h1>NETLIX</h1>
        <p class="subtitle">HashiCorp Demo Platform</p>
    </header>
    <div class="content">
        <span class="badge">Powered by HashiCorp</span>
        <div class="info">
            <h3>Platform Stack</h3>
            <p>Terraform Cloud (Stacks) &bull; HCP Vault Dedicated &bull; Vault Secrets Operator &bull; Sentinel &bull; ArgoCD</p>
        </div>
        <h2 style="margin-top: 2rem;">Trending on Netlix</h2>
        <div id="titles" class="grid"></div>
    </div>
    <div class="version">` + version + `</div>
    <script>
        fetch('/api/titles')
            .then(r => r.json())
            .then(titles => {
                const el = document.getElementById('titles');
                el.innerHTML = titles.map(t =>
                    '<div class="card"><h4>' + t.name + '</h4><span class="genre">' + t.genre + '</span> <span class="year">' + t.year + '</span></div>'
                ).join('');
            })
            .catch(() => {
                document.getElementById('titles').innerHTML = '<p style="color:#666">Could not load titles</p>';
            });
    </script>
</body>
</html>`))
}
