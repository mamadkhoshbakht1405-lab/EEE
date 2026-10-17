# ========================================================
# Stage: Frontend (Vite)
# ========================================================
FROM --platform=$BUILDPLATFORM node:26-alpine AS frontend
WORKDIR /src/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
COPY internal/web/translation /src/internal/web/translation
RUN npm run build

# ========================================================
# Stage: Builder
# ========================================================
FROM golang:1.27-alpine AS builder
WORKDIR /app
ARG TARGETARCH

RUN apk --no-cache --update add \
  build-base \
  gcc \
  curl \
  unzip

COPY . .
COPY --from=frontend /src/internal/web/dist ./internal/web/dist

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"
RUN go build -ldflags "-w -s" -o build/x-ui main.go
# Strip Windows CRLF + restore exec bit (lost when uploading from Windows/GitHub)
RUN sed -i 's/\r$//' DockerInit.sh RailwayEntrypoint.sh \
  && chmod +x DockerInit.sh RailwayEntrypoint.sh \
  && sh ./DockerInit.sh "$TARGETARCH"

# ========================================================
# Stage: Final Image of 3x-ui (Railway edition)
# ========================================================
FROM alpine
ENV TZ=Asia/Tehran
WORKDIR /app

# fail2ban removed: Railway containers have no NET_ADMIN / iptables access.
RUN apk add --no-cache --update \
  ca-certificates \
  tzdata \
  bash \
  curl \
  openssl

COPY --from=builder /app/build/ /app/
COPY --from=builder /app/RailwayEntrypoint.sh /app/
COPY --from=builder /app/internal/web/translation /app/internal/web/translation

RUN chmod +x /app/RailwayEntrypoint.sh /app/x-ui

ENV XUI_IN_DOCKER="true"
ENV XUI_MAIN_FOLDER="/app"
ENV XUI_ENABLE_FAIL2BAN="false"
ENV XUI_DB_FOLDER="/etc/x-ui"
ENV XUI_LOG_FOLDER="/var/log/x-ui"
ENV XUI_DB_TYPE=""
ENV XUI_DB_DSN=""
# NOTE: no VOLUME instruction on purpose (Railway rejects it).
# Attach a Railway Volume with mount path /etc/x-ui instead.
CMD [ "./x-ui" ]
ENTRYPOINT [ "/app/RailwayEntrypoint.sh" ]
