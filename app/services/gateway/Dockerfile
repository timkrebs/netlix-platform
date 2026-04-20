# syntax=docker/dockerfile:1.6
# Multi-stage: build SPA, build Go gateway, copy SPA into final image.
# Build context must be the repo root (`app/services/`) so we can COPY
# both the gateway source and the frontend source.

FROM node:20-alpine AS spa-builder
WORKDIR /spa
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm install --no-audit --no-fund
COPY frontend/ ./
RUN npm run build

FROM golang:1.23-alpine AS go-builder
WORKDIR /app
COPY gateway/go.mod gateway/go.sum* ./
RUN go mod download
COPY gateway/*.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /server .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=go-builder /server /server
COPY --from=spa-builder /spa/dist /var/www/spa
EXPOSE 8080
USER nonroot:nonroot
ENV STATIC_DIR=/var/www/spa
ENTRYPOINT ["/server"]
