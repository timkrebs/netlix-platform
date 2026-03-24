FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /netlix ./cmd/server

FROM alpine:3.20

RUN apk add --no-cache ca-certificates
COPY --from=builder /netlix /usr/local/bin/netlix

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

EXPOSE 8443 8080
ENTRYPOINT ["netlix"]
