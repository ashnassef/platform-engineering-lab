package main

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRequestIdempotencyKey(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		headers map[string]string
		want    string
		wantErr bool
	}{
		{
			name: "trims the primary header",
			headers: map[string]string{
				"Idempotency-Key": "  event-123  ",
			},
			want: "event-123",
		},
		{
			name: "uses the fallback header",
			headers: map[string]string{
				"X-Idempotency-Key": "fallback-456",
			},
			want: "fallback-456",
		},
		{
			name: "falls back when the primary header is blank",
			headers: map[string]string{
				"Idempotency-Key":   "   ",
				"X-Idempotency-Key": "fallback-789",
			},
			want: "fallback-789",
		},
		{
			name:    "returns empty when no header is present",
			headers: map[string]string{},
			want:    "",
		},
		{
			name: "rejects overlong values",
			headers: map[string]string{
				"Idempotency-Key": strings.Repeat("a", 129),
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		tt := tt

		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			req := httptest.NewRequest(http.MethodPost, "/", nil)
			for key, value := range tt.headers {
				req.Header.Set(key, value)
			}

			got, err := requestIdempotencyKey(req)
			if tt.wantErr {
				var bad errBadIdempotencyKey
				if !errors.As(err, &bad) {
					t.Fatalf("expected errBadIdempotencyKey, got %v", err)
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if got != tt.want {
				t.Fatalf("requestIdempotencyKey() = %q, want %q", got, tt.want)
			}
		})
	}
}
