# syntax=docker/dockerfile:1
# check=error=true

# Build:  docker build -t ioc-extractor .
# Run:    docker compose up   (see docker-compose.yml)

ARG RUBY_VERSION=3.4.8
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime packages: Tesseract OCR, Python 3, sqlite3, libvips, jemalloc
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips sqlite3 \
      tesseract-ocr tesseract-ocr-eng \
      python3 python3-venv && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    DOCLING_PYTHON="/rails/docling-venv/bin/python3"

# ── Build stage ───────────────────────────────────────────────────────────────
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git libvips libyaml-dev pkg-config \
      python3-pip && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Node.js (for CSS compilation only — not shipped in final image)
ARG NODE_VERSION=24.11.0
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    rm -rf /tmp/node-build-master

# Ruby gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

# Python docling venv — use --copies so the venv is portable between stages
# NOTE: this pulls ~2 GB of ML dependencies (torch, transformers, etc.)
RUN python3 -m venv --copies /rails/docling-venv && \
    /rails/docling-venv/bin/pip install --no-cache-dir --upgrade pip && \
    /rails/docling-venv/bin/pip install --no-cache-dir docling

# npm deps + CSS compilation
COPY package.json package-lock.json ./
RUN npm ci

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Compile SCSS → CSS, then precompile Rails assets
RUN npm run build:css
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Strip node_modules from final artifact
RUN rm -rf node_modules

# ── Final image ───────────────────────────────────────────────────────────────
FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /rails/tmp/ioc_files /rails/log && \
    chown -R 1000:1000 /rails/tmp /rails/log

USER 1000:1000

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
