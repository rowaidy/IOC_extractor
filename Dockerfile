# syntax=docker/dockerfile:1
# check=error=true

# Build:  docker build -t ioc-extractor .
# Run:    docker compose up   (see docker-compose.yml)

ARG RUBY_VERSION=3.4.8
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime packages: Tesseract OCR, Python 3, sqlite3, libvips, jemalloc
# libgomp1 is required by PyTorch (docling dependency)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips sqlite3 \
      tesseract-ocr tesseract-ocr-eng \
      python3 python3-venv python3-pip \
      libgomp1 libgfortran5 libopenblas0-pthread && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    DOCLING_PYTHON="/docling-venv/bin/python3"

# ── Build stage ───────────────────────────────────────────────────────────────
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Node.js (for CSS compilation only — stripped from final image)
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

# npm deps (including devDeps for sass/postcss)
COPY package.json package-lock.json ./
RUN npm ci

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/
RUN npm run build:css
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
RUN rm -rf node_modules

# ── Final image ───────────────────────────────────────────────────────────────
FROM base

# Install docling venv at /docling-venv (outside /rails) so the app COPY
# cannot overwrite it. System libs match because this runs in the final image.
# NOTE: pulls ~2 GB of ML dependencies (PyTorch, Transformers).
RUN python3 -m venv /docling-venv && \
    /docling-venv/bin/pip install --no-cache-dir --upgrade pip && \
    /docling-venv/bin/pip install --no-cache-dir docling

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /rails/tmp/ioc_files /rails/log && \
    chown -R 1000:1000 /rails/tmp /rails/log /docling-venv

USER 1000:1000

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
