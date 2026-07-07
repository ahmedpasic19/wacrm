# wacrm — production image for Coolify (Dockerfile deploy).
#
# Coolify setup (single container, Supabase Cloud):
#   1. Resource type: Dockerfile
#   2. Port: 3000
#   3. Domain: https://crm.digiboss.it (or your canonical URL)
#
# Build-time environment (Coolify → Build → Environment / Build Args):
#   NEXT_PUBLIC_SUPABASE_URL      — Supabase project URL
#   NEXT_PUBLIC_SUPABASE_ANON_KEY — Supabase anon key
#   NEXT_PUBLIC_SITE_URL          — e.g. https://crm.digiboss.it
#
# Runtime environment (Coolify → Environment):
#   SUPABASE_SERVICE_ROLE_KEY     — secret
#   ENCRYPTION_KEY                — 64-char hex (generate once, never rotate casually)
#   META_APP_SECRET               — Meta app secret (webhook HMAC)
#   META_APP_ID                   — Meta app ID (image-header templates)
#   NEXT_PUBLIC_SITE_URL          — same as build (safe to repeat at runtime)
#
# Optional — enable later when you use Wait automations or Flows:
#   AUTOMATION_CRON_SECRET        — then schedule Coolify tasks:
#     GET https://crm.digiboss.it/api/automations/cron  (header: x-cron-secret)
#     GET https://crm.digiboss.it/api/flows/cron        (header: x-cron-secret)
#
# Before first deploy: run all SQL files in supabase/migrations/ against your
# Supabase project, and set Supabase Auth redirect URLs to your domain.

# syntax=docker/dockerfile:1

FROM node:26-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM node:26-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_SITE_URL

ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL
ENV NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY
ENV NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL

# CI placeholders — real values are read at runtime on the server.
ENV ENCRYPTION_KEY=0000000000000000000000000000000000000000000000000000000000000000
ENV META_APP_SECRET=build-time-placeholder

RUN npm run build

FROM node:26-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

RUN addgroup -S nodejs && adduser -S nextjs -G nodejs

COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/login').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
