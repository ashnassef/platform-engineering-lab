package main

import "testing"

func TestShouldDeadLetter(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		retries    int64
		maxRetries int
		want       bool
	}{
		{
			name:       "below the limit",
			retries:    0,
			maxRetries: 3,
			want:       false,
		},
		{
			name:       "at the limit",
			retries:    3,
			maxRetries: 3,
			want:       false,
		},
		{
			name:       "above the limit",
			retries:    4,
			maxRetries: 3,
			want:       true,
		},
	}

	for _, tt := range tests {
		tt := tt

		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			got := shouldDeadLetter(tt.retries, tt.maxRetries)
			if got != tt.want {
				t.Fatalf("shouldDeadLetter(%d, %d) = %t, want %t", tt.retries, tt.maxRetries, got, tt.want)
			}
		})
	}
}
