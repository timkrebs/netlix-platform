package database

import (
	"database/sql"
	"fmt"
	"os"

	_ "github.com/lib/pq"
)

func Connect() (*sql.DB, error) {
	host := os.Getenv("DB_HOST")
	port := os.Getenv("DB_PORT")
	name := os.Getenv("DB_NAME")
	user := os.Getenv("DB_USERNAME")
	pass := os.Getenv("DB_PASSWORD")

	if port == "" {
		port = "5432"
	}

	dsn := fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=require",
		host, port, name, user, pass)

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("open: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping: %w", err)
	}

	return db, nil
}

func Migrate(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS titles (
			id    SERIAL PRIMARY KEY,
			name  TEXT NOT NULL,
			genre TEXT NOT NULL,
			year  INTEGER NOT NULL
		)
	`)
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}

	// Seed data if empty
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM titles").Scan(&count); err != nil {
		return fmt.Errorf("count: %w", err)
	}

	if count == 0 {
		_, err := db.Exec(`
			INSERT INTO titles (name, genre, year) VALUES
			('The Vault Heist', 'Action', 2024),
			('Terraform Dreams', 'Sci-Fi', 2024),
			('Sentinel Protocol', 'Thriller', 2024),
			('Cloud Nomad', 'Adventure', 2024),
			('Secret Rotation', 'Mystery', 2024)
		`)
		if err != nil {
			return fmt.Errorf("seed: %w", err)
		}
	}

	return nil
}
