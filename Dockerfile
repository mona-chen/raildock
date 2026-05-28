# syntax=docker/dockerfile:1
# check=error=true
#
# Single image for RailDock — serves the React frontend and proxies API to Rails.
#
# Build:  docker build -t raildock/raildock .
# Run:    docker run -d -p 80:80 -e DATABASE_URL=... -e RAILS_MASTER_KEY=... raildock/raildock
#
# For docker-compose example, see: https://github.com/mona-chen/raildock

ARG RUBY_VERSION=3.4.4
ARG NODE_VERSION=22

# ── Stage 1: Build React frontend ──────────────────────────────────────────
FROM docker.io/node:${NODE_VERSION}-alpine AS frontend-builder
WORKDIR /app
COPY app/package.json app/package-lock.json ./
RUN npm ci --ignore-scripts
COPY app/ .
RUN npm run build

# ── Stage 2: Install Ruby gems ─────────────────────────────────────────────
FROM docker.io/ruby:${RUBY_VERSION}-slim AS gems
WORKDIR /gem-cache
COPY backend/Gemfile backend/Gemfile.lock ./
ENV BUNDLE_PATH=/gem-cache/vendor
RUN bundle install && rm -rf ~/.bundle/

# ── Stage 3: Production image ─────────────────────────────────────────────
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails

# Install runtime dependencies: nginx, supervisor, curl, postgres client, jemalloc
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        curl nginx supervisor libjemalloc2 postgresql-client \
        && ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
        && rm -rf /var/lib/apt/lists /var/cache/apt/archives \
        # Clean default nginx config
        && rm -rf /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d/*.default

ENV RAILS_ENV=production \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so \
    PORT=3000 \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=true

# Copy gems from stage 2
COPY --from=/gems /gem-cache /usr/local/bundle

# Copy Rails app code (gems from above, code below)
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY backend/ .

# Non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Copy built frontend dist → nginx root
COPY --from=frontend-builder /app/dist /usr/share/nginx/html

# Copy nginx config for RailDock (serves static + proxies API to Puma)
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Copy supervisor config
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Run as non-root
USER 1000:1000
EXPOSE 80

# Entrypoint: prepare DB then start supervisord
COPY docker/docker-entrypoint /usr/local/bin/raildock-entrypoint
ENTRYPOINT ["/usr/local/bin/raildock-entrypoint"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]