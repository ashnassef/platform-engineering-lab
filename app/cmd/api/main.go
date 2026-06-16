package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"platform-engineering-lab/app/internal/event"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
)

const (
	queueName            = "events:queue"
	defaultMaxQueueDepth = 1000
)

var (
	rdb           *redis.Client
	maxQueueDepth int64

	requestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "api_requests_total", Help: "Total API requests"},
		[]string{"method", "path", "status"},
	)

	eventsQueued = prometheus.NewCounter(
		prometheus.CounterOpts{Name: "events_queued_total", Help: "Total events queued"},
	)

	eventsDeduplicated = prometheus.NewCounter(
		prometheus.CounterOpts{Name: "events_deduplicated_total", Help: "Total duplicate/idempotent event submissions replayed"},
	)

	eventsBackpressured = prometheus.NewCounter(
		prometheus.CounterOpts{Name: "events_backpressured_total", Help: "Total event submissions rejected due to queue backpressure"},
	)

	redisErrors = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "api_redis_errors_total", Help: "Total Redis errors by operation"},
		[]string{"operation"},
	)

	queueDepth = prometheus.NewGaugeFunc(
		prometheus.GaugeOpts{Name: "events_queue_depth", Help: "Current Redis event queue depth"},
		func() float64 {
			if rdb == nil {
				return -1
			}

			ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
			defer cancel()

			n, err := rdb.LLen(ctx, queueName).Result()
			if err != nil {
				return -1
			}

			return float64(n)
		},
	)
)

func main() {
	redisAddr := getenv("REDIS_ADDR", "localhost:6379")
	maxQueueDepth = int64(getenvInt("MAX_QUEUE_DEPTH", defaultMaxQueueDepth))

	rdb = redis.NewClient(&redis.Options{Addr: redisAddr})

	prometheus.MustRegister(
		requestsTotal,
		eventsQueued,
		eventsDeduplicated,
		eventsBackpressured,
		redisErrors,
		queueDepth,
	)

	http.HandleFunc("/healthz", handleHealth)
	http.HandleFunc("/readyz", handleReady)
	http.HandleFunc("/events", instrument("/events", handleCreateEvent))
	http.HandleFunc("/events/", instrument("/events/{id}", handleGetEvent))
	http.Handle("/metrics", promhttp.Handler())

	log.Printf("api listening on :8080, redis=%s, max_queue_depth=%d", redisAddr, maxQueueDepth)
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok\n"))
}

func handleReady(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 500*time.Millisecond)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		redisErrors.WithLabelValues("ping").Inc()
		http.Error(w, "redis unavailable", http.StatusServiceUnavailable)
		return
	}

	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ready\n"))
}

func handleCreateEvent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 1*time.Second)
	defer cancel()

	depth, err := rdb.LLen(ctx, queueName).Result()
	if err != nil {
		redisErrors.WithLabelValues("queue_depth").Inc()
		http.Error(w, "read queue depth", http.StatusServiceUnavailable)
		return
	}

	if depth >= maxQueueDepth {
		eventsBackpressured.Inc()
		http.Error(w, "queue depth limit reached", http.StatusTooManyRequests)
		return
	}

	idempotencyKey, err := requestIdempotencyKey(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if idempotencyKey != "" {
		replayed, err := replayIdempotentEvent(ctx, w, idempotencyKey)
		if err != nil {
			redisErrors.WithLabelValues("idempotency_lookup").Inc()
			http.Error(w, "read idempotency key", http.StatusServiceUnavailable)
			return
		}
		if replayed {
			return
		}
	}

	now := time.Now().Unix()
	ev := event.Event{
		ID:             newID(),
		Status:         "queued",
		CreatedAt:      now,
		IdempotencyKey: idempotencyKey,
	}

	idempotencyReserved := false

	if idempotencyKey != "" {
		ok, err := rdb.SetNX(ctx, "idempotency:"+idempotencyKey, ev.ID, 24*time.Hour).Result()
		if err != nil {
			redisErrors.WithLabelValues("idempotency_reserve").Inc()
			http.Error(w, "reserve idempotency key", http.StatusServiceUnavailable)
			return
		}

		if !ok {
			replayed, err := replayIdempotentEvent(ctx, w, idempotencyKey)
			if err != nil {
				redisErrors.WithLabelValues("idempotency_replay").Inc()
				http.Error(w, "read idempotent event", http.StatusServiceUnavailable)
				return
			}
			if replayed {
				return
			}

			http.Error(w, "idempotent request is already in progress", http.StatusConflict)
			return
		}

		idempotencyReserved = true
	}

	data, err := json.Marshal(ev)
	if err != nil {
		http.Error(w, "marshal event", http.StatusInternalServerError)
		return
	}

	key := "events:" + ev.ID

	if err := rdb.Set(ctx, key, data, 24*time.Hour).Err(); err != nil {
		redisErrors.WithLabelValues("store_event").Inc()
		cleanupReservation(ctx, idempotencyReserved, idempotencyKey)
		http.Error(w, "store event", http.StatusServiceUnavailable)
		return
	}

	if err := rdb.RPush(ctx, queueName, ev.ID).Err(); err != nil {
		redisErrors.WithLabelValues("queue_event").Inc()
		cleanupReservation(ctx, idempotencyReserved, idempotencyKey)
		_ = rdb.Del(ctx, key).Err()
		http.Error(w, "queue event", http.StatusServiceUnavailable)
		return
	}

	eventsQueued.Inc()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(ev)
}

func handleGetEvent(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/events/")
	if id == "" {
		http.Error(w, "missing event id", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 1*time.Second)
	defer cancel()

	data, err := rdb.Get(ctx, "events:"+id).Bytes()
	if err == redis.Nil {
		http.Error(w, "event not found", http.StatusNotFound)
		return
	}
	if err != nil {
		redisErrors.WithLabelValues("read_event").Inc()
		http.Error(w, "read event", http.StatusServiceUnavailable)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write(data)
}

func replayIdempotentEvent(ctx context.Context, w http.ResponseWriter, idempotencyKey string) (bool, error) {
	id, err := rdb.Get(ctx, "idempotency:"+idempotencyKey).Result()
	if err == redis.Nil {
		return false, nil
	}
	if err != nil {
		return false, err
	}

	data, err := rdb.Get(ctx, "events:"+id).Bytes()
	if err == redis.Nil {
		http.Error(w, "idempotent request is still being created", http.StatusConflict)
		return true, nil
	}
	if err != nil {
		return false, err
	}

	eventsDeduplicated.Inc()

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Idempotent-Replay", "true")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)

	return true, nil
}

func requestIdempotencyKey(r *http.Request) (string, error) {
	value := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if value == "" {
		value = strings.TrimSpace(r.Header.Get("X-Idempotency-Key"))
	}

	if len(value) > 128 {
		return "", errBadIdempotencyKey{}
	}

	return value, nil
}

type errBadIdempotencyKey struct{}

func (errBadIdempotencyKey) Error() string {
	return "idempotency key too long"
}

func cleanupReservation(ctx context.Context, reserved bool, idempotencyKey string) {
	if reserved && idempotencyKey != "" {
		_ = rdb.Del(ctx, "idempotency:"+idempotencyKey).Err()
	}
}

func instrument(path string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next(rec, r)
		requestsTotal.WithLabelValues(r.Method, path, http.StatusText(rec.status)).Inc()
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func newID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return hex.EncodeToString([]byte(time.Now().Format(time.RFC3339Nano)))
	}
	return hex.EncodeToString(b)
}

func getenv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func getenvInt(key string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
}
