# Stage 1: Build the frontend
FROM node:20.19.0-alpine AS builder

# Install pnpm
RUN npm install -g pnpm@8.6.12

WORKDIR /app

# Copy webapp source
COPY airbyte-webapp/ ./

# Install dependencies (skip prepare/githooks)
RUN pnpm install --frozen-lockfile --ignore-scripts

# Build args for env vars baked into the Vite bundle at build time
ARG REACT_APP_API_URL
ARG REACT_APP_KEYCLOAK_BASE_URL

RUN pnpm run build

# Stage 2: Serve with nginx
FROM nginx:1.27-alpine

COPY docker/frontend/nginx.conf /etc/nginx/conf.d/default.conf

COPY --from=builder /app/build/app /usr/share/nginx/html

EXPOSE 80
