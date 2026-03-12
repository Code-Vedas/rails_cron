---
title: Usage
nav_order: 5
permalink: /usage
---

# 🚀 Usage

This page explains how to register cron jobs, run the scheduler, and use the provided CLI and Rake tasks.

---

## 🧩 Registering Cron Jobs

Define your recurring tasks during application boot (e.g. in `config/initializers/kaal_jobs.rb`):

```ruby
Kaal.register(
  key: "reports:weekly_summary",
  cron: "0 9 * * 1", # every Monday at 9 AM
  enqueue: ->(fire_time:, idempotency_key:) {
    WeeklySummaryJob.perform_later(fire_time: fire_time, key: idempotency_key)
  }
)
```

**Parameters:**

| Name              | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `key`             | Unique identifier for the cron task                  |
| `cron`            | Cron expression (`"*/15 * * * *"`, `"@daily"`, etc.) |
| `enqueue`         | Lambda or proc to run when the cron fires            |
| `fire_time`       | UTC time when the tick was due                       |
| `idempotency_key` | Deterministic key used to prevent duplicate runs     |

> 💡 Each task is dispatched **exactly once**, even if multiple Rails or Sidekiq nodes are running.

---

## 🕒 Starting the Scheduler

`Kaal` does **not** auto-start by default. Start it explicitly via `Kaal.start!` or `kaal:start`.

You can start the scheduler loop in one of two ways:

### Option 1 — Inline in Rails

```ruby
# config/initializers/kaal.rb
Kaal.start!
```

> Use this mainly for development/testing. In production, prefer a standalone scheduler process.

### Option 2 — Standalone process (recommended for production)

```bash
bundle exec rails kaal:start
```

Example **Procfile** entry:

```procfile
web:       bundle exec puma -C config/puma.rb
scheduler: bundle exec rails kaal:start
```

Avoid running scheduler inside web server processes by default. Keep scheduler lifecycle independent from request-serving processes.

### systemd Example

```ini
[Unit]
Description=Kaal scheduler
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/apps/myapp/current
Environment=RAILS_ENV=production
ExecStart=/usr/bin/bash -lc 'bundle exec rails kaal:start'
ExecStartPre=/usr/bin/bash -lc 'bundle exec rails kaal:status'
ExecReload=/bin/kill -TERM $MAINPID
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Kubernetes Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kaal-scheduler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kaal-scheduler
  template:
    metadata:
      labels:
        app: kaal-scheduler
    spec:
      containers:
        - name: scheduler
          image: your-app:latest
          command: ["bash", "-lc", "bundle exec rails kaal:start"]
```

For Kubernetes, the scheduler is the container's main process; if it exits, Kubernetes restarts it.  
Do not use `kaal:status` as a scheduler liveness/readiness probe because it runs in a separate process and cannot inspect in-memory scheduler state.

Prefer:

- Process-level checks from your runtime/supervisor.
- A shared heartbeat/lease (Redis, Postgres, pidfile, etc.) written by the scheduler and read by probes.

---

## 🧰 CLI & Rake Tasks

### Explain and Preview Cron Expressions

```bash
kaal explain "*/15 * * * *"
# => Every 15 minutes

kaal next "0 9 * * 1" --count 3
# => 2025-11-03 09:00:00 UTC
# => 2025-11-10 09:00:00 UTC
# => 2025-11-17 09:00:00 UTC
```

### Rails Tasks

```bash
bin/rails kaal:start          # Start scheduler loop
bin/rails kaal:tick           # Trigger a single scheduler tick
bin/rails kaal:status         # Show active configuration & registry
bin/rails kaal:explain["*/5 * * * *"] # Humanize a cron expression
```

---

## 🧠 Cron Utilities

`Kaal` provides convenience helpers for validating, simplifying, and linting cron expressions.

```ruby
Kaal.valid?("*/5 * * * *")
# => true

Kaal.simplify("0 0 * * *")
# => "@daily"

Kaal.lint("*/61 * * * *")
# => ["minute step '61' is out of range. Allowed step: 1-60.", "Invalid cron expression '*/61 * * * *'. Examples: '*/5 * * * *', '@daily'."]

Kaal.to_human("0 9 * * 1")
# => "At 09:00 every Monday"

Kaal.to_human("@daily")
# => "Daily"

Kaal.to_human("0 9 * * 1", locale: :fr)
# => Uses :fr locale when available
```

Supported predefined macros include:
`@yearly`, `@annually`, `@monthly`, `@weekly`, `@daily`, `@midnight`, `@hourly`.

`Kaal.simplify` raises `ArgumentError` for invalid expressions with helpful examples:

```ruby
Kaal.simplify("not-a-cron")
# raises ArgumentError: Invalid cron expression 'not-a-cron'. Examples: '*/5 * * * *', '@daily'.
```

`Kaal.to_human` also raises `ArgumentError` for invalid expressions and unsupported macros.

---

## 🔍 Checking Status

```bash
bin/rails kaal:status
```

Displays the current configuration, backend adapter, and registered jobs.

Example output:

```bash
Kaal v1.0.0
Backend adapter: Redis
Tick interval: 5s
Registered jobs:
  - reports:weekly_summary ("0 9 * * 1")
Next tick: 2025-11-10 09:00:00 UTC
```

---

## 🧠 Tips

- Use `Rails.logger.info` inside your job block for observability.
- Use `window_lookback` to replay missed ticks (e.g., after downtime).
- Never duplicate the same `key` — it uniquely identifies each job.
- The scheduler gracefully stops on `TERM` or `INT`, finishing the current tick first.
