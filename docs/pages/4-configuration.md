---
title: Configuration
nav_order: 4
permalink: /configuration
---

# ⚙️ Configuration

RailsCron can be configured globally through an initializer.  
All configuration options are optional and can be customized per environment.

---

## 🧩 Example Configuration

```ruby
# config/initializers/rails_cron.rb
RailsCron.configure do |c|
  # Choose your distributed lock adapter
  # c.lock_adapter = RailsCron::Lock::RedisAdapter.new(redis)
  # c.lock_adapter = RailsCron::Lock::PostgresAdapter.new
  # c.lock_adapter = RailsCron::Lock::MemoryAdapter.new # single-node only (not for production)

  # Frequency of scheduler ticks (in seconds)
  c.tick_interval    = 5

  # Replays missed ticks that occurred within this time window (in seconds)
  c.window_lookback  = 120

  # Optional: trigger ticks slightly early for lookahead scenarios
  c.window_lookahead = 0

  # Lock duration (seconds) — should exceed your longest tick/dispatch
  c.lease_ttl        = 60

  # Optional prefix for Redis/Postgres keys
  c.namespace        = "railscron"

  # Optional timezone for cron evaluation
  # c.time_zone = "America/Toronto"

  # Optional logger override
  # c.logger = Logger.new($stdout, level: :info)
end
```

---

## 🔧 Configuration Reference

| Setting            | Type    | Default                     | Description                                                                                |
| ------------------ | ------- | --------------------------- | ------------------------------------------------------------------------------------------ |
| `lock_adapter`     | Object  | `nil`                       | Distributed lock implementation. Use **Redis** or **Postgres** in multi-node environments. |
| `tick_interval`    | Integer | `5`                         | Seconds between scheduler ticks.                                                           |
| `window_lookback`  | Integer | `120`                       | How far back the scheduler will replay missed ticks.                                       |
| `window_lookahead` | Integer | `0`                         | How far ahead to pre-trigger upcoming ticks (optional).                                    |
| `lease_ttl`        | Integer | `60`                        | Duration for distributed lock lease in seconds.                                            |
| `namespace`        | String  | `"railscron"`               | Key prefix used for locks and dispatch logs.                                               |
| `logger`           | Logger  | `Rails.logger` (if present) | Logger used for scheduler messages.                                                        |
| `time_zone`        | String  | System default              | Optional timezone for evaluating cron expressions.                                         |

---

## 🔐 Lock Adapters

### Redis Adapter

```ruby
RailsCron.configure do |c|
  c.lock_adapter = RailsCron::Lock::Redis.new(
    url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")
  )
end
```

- Uses `SET NX PX` semantics for distributed locks.
- Low latency, great for production.

---

### Postgres Adapter

```ruby
RailsCron.configure do |c|
  c.lock_adapter = RailsCron::Lock::Postgres.new(
    connection: ActiveRecord::Base.connection
  )
end
```

- Uses `pg_try_advisory_lock`.
- Ideal for environments without Redis.

---

### Memory Adapter

```ruby
RailsCron.configure do |c|
  c.lock_adapter = RailsCron::Lock::Memory.new
end
```

- In-process only — suitable for **development or testing**.
- Not safe for multi-node deployments.

---

## 🧱 Registering Jobs

After configuration, register your cron tasks (usually in `config/initializers/rails_cron_jobs.rb`):

```ruby
RailsCron.register(
  key: "cleanup:stale_sessions",
  cron: "*/15 * * * *", # every 15 minutes
  enqueue: ->(fire_time:, idempotency_key:) {
    CleanupSessionsJob.perform_later(fire_time: fire_time, key: idempotency_key)
  }
)
```

**Parameters:**

| Parameter         | Description                                                               |
| ----------------- | ------------------------------------------------------------------------- |
| `key`             | Unique identifier for the cron job.                                       |
| `cron`            | Cron expression (supports standard syntax and `@daily`, `@hourly`, etc.). |
| `enqueue`         | Lambda to execute when the tick fires.                                    |
| `fire_time`       | UTC time when the job was scheduled to run.                               |
| `idempotency_key` | Deterministic key to prevent duplicate dispatches.                        |

---

## 🕒 Starting the Scheduler

You can start the scheduler loop either inline or as a dedicated process.

### Option 1 — Inline (inside Rails)

```ruby
# config/initializers/rails_cron.rb
RailsCron.start!
```

Starts automatically when Rails boots.

### Option 2 — Standalone Process (Recommended)

```bash
bundle exec rails rails_cron:start
```

**Procfile Example:**

```procfile
web:       bundle exec puma -C config/puma.rb
scheduler: bundle exec rails rails_cron:start
```

> ✅ Best practice: run one scheduler per environment — multiple nodes can start it safely (only one acquires the lock per tick).

---

## 🌍 Time Zone Control

By default, cron expressions use the system’s timezone.
To override:

```ruby
RailsCron.configure do |c|
  c.time_zone = "America/Toronto"
end
```

---

## 🧠 Logging

RailsCron uses the Rails logger by default. You can customize it:

```ruby
RailsCron.configure do |c|
  c.logger = Logger.new($stdout, level: :debug)
end
```

---

## 🧩 Multiple Nodes

You can safely run multiple schedulers (e.g., in Kubernetes, ECS, or multiple dynos).
Distributed locks ensure **only one** node dispatches jobs for each tick.

**Checklist:**

- Use Redis or Postgres lock adapter.
- Ensure `lease_ttl` is longer than your job dispatch time.
- Avoid heavy logic inside the `enqueue` lambda — just enqueue your job.

---

## ✅ Quick Commands

```bash
# Show configuration and registered jobs
bin/rails rails_cron:status

# Manually trigger one scheduler tick
bin/rails rails_cron:tick

# Humanize a cron expression
bin/rails rails_cron:explain["*/15 * * * *"]
```
