# ==========================
# Build Stage
# ==========================

FROM golang:1.21 AS builder

WORKDIR /app

COPY go.mod .
COPY go.sum .

RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o evaluation-service .

# ==========================
# Runtime Stage
# ==========================

FROM alpine:3.20

WORKDIR /app

RUN apk --no-cache add ca-certificates

COPY --from=builder /app/evaluation-service .

EXPOSE 8004

CMD ["./evaluation-service"]