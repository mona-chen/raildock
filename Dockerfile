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
ARG NODE_VERSION=24
ARG RAILDOCK_VERSION=unknown

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
# Install build tools for native gem extensions (bigdecimal, pg, psych, etc.)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        build-essential libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
ENV BUNDLE_PATH=/gem-cache/vendor
RUN bundle install && rm -rf ~/.bundle/

# ── Stage 3: Production image ─────────────────────────────────────────────
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base
ARG RAILDOCK_VERSION=unknown
WORKDIR /rails

# Install runtime dependencies: nginx, supervisor, curl, postgres client, jemalloc
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        curl nginx supervisor libjemalloc2 postgresql-client \
    && apt-get install -y libcap2-bin \
    && setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx \
    && ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives \
    && rm -rf /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d/*.default

ENV RAILS_ENV=production \
    BUNDLE_PATH=/usr/local/bundle/vendor \
    BUNDLE_DEPLOYMENT=true \
    BUNDLE_WITHOUT=development:test \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so \
    PORT=3000 \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=true \
    RAILDOCK_VERSION=${RAILDOCK_VERSION} \
    PATH=/usr/local/bundle/vendor/ruby/3.4.0/bin:/usr/local/bundle/vendor/bin:/usr/local/bin:$PATH

# Copy frozen gem cache from stage 2
COPY --from=gems /gem-cache /usr/local/bundle

# Copy the Rails app code
COPY backend/ .

# Non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Copy built frontend dist → nginx root
COPY --from=frontend-builder /app/dist /usr/share/nginx/html

# Copy nginx config for RailDock (serves static + proxies API to Puma)
COPY docker/nginx.conf /etc/nginx/nginx.conf

# Copy supervisor config
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Entrypoint: must chmod before switching to non-root user
COPY --chmod=755 docker/docker-entrypoint /usr/local/bin/raildock-entrypoint

RUN mkdir -p /var/log/supervisor /var/log/nginx /var/lib/nginx /tmp/nginx /tmp/pids && \
    mkdir -p /rails/tmp /rails/log /rails/storage && \
    chown -R rails:rails /var/log/supervisor /var/log/nginx /var/lib/nginx /tmp/nginx /tmp/pids /usr/share/nginx/html /rails

# Run as non-root
USER 1000:1000
EXPOSE 80

# Entrypoint: prepare DB then start supervisord
ENTRYPOINT ["/usr/local/bin/raildock-entrypoint"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
