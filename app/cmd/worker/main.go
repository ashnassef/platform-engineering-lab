package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	queueName      = "events:queue"
	processingName = "events:processing"
	deadName       = "events:dead"
)

var (
	rdb        *redis.Client
	maxRetries int

	jobsProcessed = prometheus.NewCounter(
		prometheus.CounterOpts{Name: "worker_jobs_processed_total", Help: "Total jobs processed"},
	)

	jobsFailed = prometheus.NewCounter(
		prometheus.CounterOpts{Name: "worker_jobs_failed_total", Help: "Total jobs failed"},
	)

	jobsRetried = prometheus.NewCounter(
		prometheus.CounterOpts{Name: "worker_jobs_retried_total", Help: "Total jobs retried"},
	)

	jobsDeadLettered = prometheus.NewCounter(
		prometheus.CounterOpts{Name: "worker_jobs_dead_lettered_total", Help: "Total jobs moved to the dead-letter queue"},
	)

	jobsDeduplicated = prometheus.NewCounter(
		prometheus.CounterOpts{Name: "worker_jobs_deduplicated_total", Help: "Total already-completed jobs skipped"},
	)

	processingDepth = prometheus.NewGaugeFunc(
		prometheus.GaugeOpts{Name: "events_processing_depth", Help: "Current Redis processing queue depth"},
		func() float64 {
			return queueLen(processingName)
		},
	)

	deadLetterDepth = prometheus.NewGaugeFunc(
		prometheus.GaugeOpts{Name: "events_dead_letter_depth", Help: "Current Redis dead-letter queue depth"},
		func() float64 {
			return queueLen(deadName)
		},
	)
)

func main() {
	redisAddr := getenv("REDIS_ADDR", "localhost:6379")
	maxRetries = getenvInt("MAX_RETRIES", 3)

	rdb = redis.NewClient(&redis.Options{Addr: redisAddr})

	prometheus.MustRegister(
		jobsProcessed,
		jobsFailed,
		jobsRetried,
		jobsDeadLettered,
		jobsDeduplicated,
		processingDepth,
		deadLetterDepth,
	)

	go func() {
		http.Handle("/metrics", promhttp.Handler())
		http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("ok\n"))
		})
		log.Fatal(http.ListenAndServe(":9091", nil))
	}()

	log.Printf("worker started, redis=%s, max_retries=%d", redisAddr, maxRetries)

	for {
		id, err := reserveJob()
		if err != nil {
			if errors.Is(err, redis.Nil) || errors.Is(err, context.DeadlineExceeded) {
				continue
			}

			jobsFailed.Inc()
			log.Printf("queue reserve failed: %v", err)
			time.Sleep(time.Second)
			continue
		}

		if err := processWithTimeout(id); err != nil {
			jobsFailed.Inc()
			log.Printf("process event %s failed: %v", id, err)

			if failErr := handleFailure(id, err); failErr != nil {
				log.Printf("failure handling for event %s failed: %v", id, failErr)
			}

			continue
		}

		if err := ackJob(id); err != nil {
			jobsFailed.Inc()
			log.Printf("ack event %s failed: %v", id, err)
			continue
		}

		jobsProcessed.Inc()
		log.Printf("processed event %s", id)
	}
}

func reserveJob() (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	return rdb.BRPopLPush(ctx, queueName, processingName, 10*time.Second).Result()
}

func processWithTimeout(id string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	return process(ctx, id)
}

func process(ctx context.Context, id string) error {
	key := "events:" + id

	data, err := rdb.Get(ctx, key).Bytes()
	if err == redis.Nil {
		return fmt.Errorf("event payload missing")
	}
	if err != nil {
		return err
	}

	var ev event.Event
	if err := json.Unmarshal(data, &ev); err != nil {
		return err
	}

	if ev.Status == "processed" || ev.Status == "dead_lettered" {
		jobsDeduplicated.Inc()
		return nil
	}

	ev.Status = "processing"
	processing, err := json.Marshal(ev)
	if err != nil {
		return err
	}

	if err := rdb.Set(ctx, key, processing, 24*time.Hour).Err(); err != nil {
		return err
	}

	time.Sleep(300 * time.Millisecond)

	ev.Status = "processed"
	ev.ProcessedAt = time.Now().Unix()
	ev.LastError = ""

	updated, err := json.Marshal(ev)
	if err != nil {
		return err
	}

	return rdb.Set(ctx, key, updated, 24*time.Hour).Err()
}

func ackJob(id string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	if err := rdb.LRem(ctx, processingName, 1, id).Err(); err != nil {
		return err
	}

	_ = rdb.Del(ctx, retryKey(id)).Err()

	return nil
}

func handleFailure(id string, cause error) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	retries, err := rdb.Incr(ctx, retryKey(id)).Result()
	if err != nil {
		return err
	}

	if shouldDeadLetter(retries, maxRetries) {
		if err := recordFailureState(ctx, id, "dead_lettered", int(retries), cause); err != nil {
			return err
		}

		if err := rdb.LPush(ctx, deadName, id).Err(); err != nil {
			return err
		}

		if err := rdb.LRem(ctx, processingName, 1, id).Err(); err != nil {
			return err
		}

		jobsDeadLettered.Inc()
		log.Printf("dead-lettered event %s after %d attempts", id, retries)
		return nil
	}

	if err := recordFailureState(ctx, id, "queued", int(retries), cause); err != nil {
		return err
	}

	if err := rdb.RPush(ctx, queueName, id).Err(); err != nil {
		return err
	}

	if err := rdb.LRem(ctx, processingName, 1, id).Err(); err != nil {
		return err
	}

	jobsRetried.Inc()
	log.Printf("requeued event %s after failure; retry=%d/%d", id, retries, maxRetries)

	return nil
}

func recordFailureState(ctx context.Context, id string, status string, retries int, cause error) error {
	key := "events:" + id

	var ev event.Event

	data, err := rdb.Get(ctx, key).Bytes()
	if err == nil {
		if unmarshalErr := json.Unmarshal(data, &ev); unmarshalErr != nil {
			ev = event.Event{}
		}
	} else if err != redis.Nil {
		return err
	}

	if ev.ID == "" {
		ev.ID = id
	}

	if ev.CreatedAt == 0 {
		ev.CreatedAt = time.Now().Unix()
	}

	ev.Status = status
	ev.RetryCount = retries
	ev.LastError = cause.Error()

	if status == "dead_lettered" {
		ev.DeadLetteredAt = time.Now().Unix()
	}

	updated, err := json.Marshal(ev)
	if err != nil {
		return err
	}

	return rdb.Set(ctx, key, updated, 24*time.Hour).Err()
}

func retryKey(id string) string {
	return "events:" + id + ":retries"
}

func shouldDeadLetter(retries int64, maxRetries int) bool {
	return retries > int64(maxRetries)
}

func queueLen(name string) float64 {
	if rdb == nil {
		return -1
	}

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	n, err := rdb.LLen(ctx, name).Result()
	if err != nil {
		return -1
	}

	return float64(n)
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
