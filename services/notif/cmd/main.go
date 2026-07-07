package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"
)

type Event struct {
	ID      int       `json:"id"`
	Kind    string    `json:"kind"`
	At      time.Time `json:"at"`
	Message string    `json:"message"`
}

var events = []Event{
	{1, "promo.created", time.Now().Add(-2 * time.Hour), "Nouvelle promo M2 IW"},
	{2, "salle.booked", time.Now().Add(-30 * time.Minute), "Salle A-101 réservée"},
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func main() {
	port := envOr("PORT", "8080")
	levelStr := envOr("LOG_LEVEL", "info")
	var level slog.Level
	_ = level.UnmarshalText([]byte(levelStr))
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})))

	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"ok": true, "service": "notif"})
	})
	http.HandleFunc("/events", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(events)
	})

	slog.Info("notif up", "port", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
