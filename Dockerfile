# Stage 1 — build
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y \
    curl xz-utils libxml2-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG ZIG_VERSION=0.16.0
RUN curl -sL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
    | tar -xJ -C /opt && \
    ln -s "/opt/zig-linux-x86_64-${ZIG_VERSION}/zig" /usr/local/bin/zig

WORKDIR /build
COPY . .
RUN zig build -Doptimize=ReleaseSafe

# Stage 2 — runtime
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    libxml2 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/zig-out/bin/sol-server ./sol-server

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["./sol-server"]
