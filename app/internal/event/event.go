package event

type Event struct {
	ID             string `json:"id"`
	Status         string `json:"status"`
	CreatedAt      int64  `json:"created_at"`
	ProcessedAt    int64  `json:"processed_at,omitempty"`
	RetryCount     int    `json:"retry_count,omitempty"`
	LastError      string `json:"last_error,omitempty"`
	DeadLetteredAt int64  `json:"dead_lettered_at,omitempty"`
	IdempotencyKey string `json:"idempotency_key,omitempty"`
}
