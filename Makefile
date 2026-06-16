.PHONY: test build up down logs

test:
	go test ./...

build:
	docker compose build

up:
	docker compose up

down:
	docker compose down

logs:
	docker compose logs -f
