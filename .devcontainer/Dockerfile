FROM debian:bookworm-slim

WORKDIR /app

# Install only the pieces needed to act as a lightweight XHTTP edge relay.
RUN echo "📦 Installing relay dependencies..." && \
    apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates curl gettext-base nginx-light openssl python3 tzdata \
    && echo "✅ Relay dependencies installed successfully" \
    && rm -rf /var/lib/apt/lists/*

COPY install.sh /app/install.sh
COPY nginx.conf.template /app/nginx.conf.template
COPY config.json /app/config.json
COPY startup.sh /app/startup.sh

RUN chmod +x /app/install.sh /app/startup.sh && \
    /app/install.sh

CMD ["/app/startup.sh"]
