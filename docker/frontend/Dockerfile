# Stage 1: Build the frontend
# Use non-alpine so bash, curl, and standard tools are available (needed by build scripts)
FROM node:20.19.0 AS builder

RUN npm install -g pnpm@8.6.12

# Install jq (needed by load-declarative-schema.sh to parse PyPI response)
RUN apt-get update && apt-get install -y --no-install-recommends jq && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy connector builder resources (load-declarative-schema.sh reads ../airbyte-connector-builder-resources/CDK_VERSION)
COPY airbyte-connector-builder-resources/ ./airbyte-connector-builder-resources/

# Copy webapp source into a subdir so relative paths (../) resolve correctly
COPY airbyte-webapp/ ./airbyte-webapp/

WORKDIR /app/airbyte-webapp

# Install dependencies (skip prepare/githooks)
RUN pnpm install --frozen-lockfile --ignore-scripts

# Build args — REACT_APP_* vars are baked into the Vite bundle at build time
ARG REACT_APP_API_URL
ARG REACT_APP_KEYCLOAK_BASE_URL

RUN pnpm run build

# Stage 2: Serve with nginx (lean final image)
FROM nginx:1.27-alpine

COPY docker/frontend/nginx.conf /etc/nginx/conf.d/default.conf

COPY --from=builder /app/airbyte-webapp/build/app /usr/share/nginx/html

EXPOSE 80
