---
title: Usage
nav_order: 5
permalink: /usage
---

# 🚀 Usage

This page explains how to register cron jobs, run the scheduler, and use the provided CLI and Rake tasks.

---

## 🧩 Registering Cron Jobs

Define your recurring tasks during application boot (e.g. in `config/initializers/rails_crons_jobs.rb`):

```ruby
RailsCron.register(
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

You can start the scheduler loop in one of two ways:

### Option 1 — Inline in Rails

```ruby
# config/initializers/rails_cron.rb
RailsCron.start!
```

> This starts the scheduler automatically when Rails boots.

### Option 2 — Standalone process (recommended for production)

```bash
bundle exec rails rails_cron:start
```

Example **Procfile** entry:

```procfile
web:       bundle exec puma -C config/puma.rb
scheduler: bundle exec rails rails_cron:start
```

---

## 🧰 CLI & Rake Tasks

### Explain and Preview Cron Expressions

```bash
rails-crons explain "*/15 * * * *"
# => Every 15 minutes

rails-crons next "0 9 * * 1" --count 3
# => 2025-11-03 09:00:00 UTC
# => 2025-11-10 09:00:00 UTC
# => 2025-11-17 09:00:00 UTC
```

### Rails Tasks

```bash
bin/rails rails_cron:start          # Start scheduler loop
bin/rails rails_cron:tick           # Trigger a single scheduler tick
bin/rails rails_cron:status         # Show active configuration & registry
bin/rails rails_cron:explain["*/5 * * * *"] # Humanize a cron expression
```

---

## 🔍 Checking Status

```bash
bin/rails rails_cron:status
```

Displays the current configuration, lock adapter, and registered jobs.

Example output:

```
RailsCron v1.0.0
Lock adapter: Redis
Tick interval: 5s
Registered jobs:
  - reports:weekly_summary ("0 9 * * 1")
Next tick: 2025-11-10 09:00:00 UTC
```

---

## 🧠 Tips

* Use `Rails.logger.info` inside your job block for observability.
* Use `window_lookback` to replay missed ticks (e.g., after downtime).
* Never duplicate the same `key` — it uniquely identifies each job.
* The scheduler gracefully stops on `TERM` or `INT`, finishing the current tick first.
