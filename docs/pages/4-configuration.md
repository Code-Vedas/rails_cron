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
  # c.lock_adapter = RailsCron::Lock::RedisAdapter.new(Redis.new(url: ENV["REDIS_URL"]))
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
  
  # Missed-run recovery (enabled by default)
  # c.enable_dispatch_recovery = true
  # c.recovery_window = 86_400 # 24 hours
  
  # Dispatch logging for audit trail and efficient recovery
  # c.enable_log_dispatch_registry = true
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
| `enable_log_dispatch_registry` | Boolean | `false`          | Enable dispatch logging for audit trail and recovery.                                      |
| `enable_dispatch_recovery` | Boolean | `true`                  | Automatically recover missed runs after downtime.                                          |
| `recovery_window`  | Integer | `86400` (24 hours)          | How far back to look for missed runs during recovery (in seconds).                         |
| `recovery_startup_jitter` | Integer | `5`                  | Max random delay (seconds) before recovery to reduce lock contention on cluster restarts.  |

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

## 🔄 Missed-Run Recovery

**Automatic Recovery** (enabled by default) ensures that cron jobs that should have executed during downtime are automatically recovered when the scheduler starts.

### How It Works

1. **On Startup**: Before the main scheduler loop begins, RailsCron looks back over a configurable window (default: 24 hours)
2. **Computes Missed Runs**: For each registered cron job, it calculates which executions should have occurred
3. **Checks Dispatch Log**: If dispatch logging is enabled, it skips runs that were already executed
4. **Re-enqueues**: Missed runs are enqueued using the same lock mechanism to prevent duplicates

### Configuration

```ruby
RailsCron.configure do |c|
  # Enable automatic recovery (default: true)
  c.enable_dispatch_recovery = true
  
  # How far back to look for missed runs (default: 24 hours)
  c.recovery_window = 86_400 # in seconds
  
  # Random delay before recovery to reduce contention (default: 5 seconds)
  c.recovery_startup_jitter = 5
  
  # Enable dispatch logging for efficient recovery (default: false)
  c.enable_log_dispatch_registry = true
end
```

### Recovery Options

| Setting                       | Type    | Default   | Description                                                                                     |
| ----------------------------- | ------- | --------- | ----------------------------------------------------------------------------------------------- |
| `enable_dispatch_recovery`    | Boolean | `true`    | Automatically recover missed runs on startup.                                                   |
| `recovery_window`             | Integer | `86400`   | How far back to look for missed runs (in seconds). 24 hours covers typical overnight downtimes. |
| `recovery_startup_jitter`     | Integer | `5`       | Max random delay (0-N seconds) before recovery starts. Reduces lock contention on cluster restarts. |
| `enable_log_dispatch_registry`| Boolean | `false`   | When enabled, recovery checks dispatch log first to avoid re-enqueueing already-executed jobs.  |

### Interaction with Dispatch Logging

When both recovery and dispatch logging are enabled:

```ruby
RailsCron.configure do |c|
  c.enable_dispatch_recovery = true
  c.enable_log_dispatch_registry = true
  c.lock_adapter = RailsCron::Lock::RedisAdapter.new(Redis.new(url: ENV["REDIS_URL"]))
end
```

**Benefits:**
- **Efficient Recovery**: The dispatch log is checked first, avoiding unnecessary lock attempts for already-executed jobs
- **Audit Trail**: See exactly which jobs were recovered vs. which were already executed
- **Reduced Contention**: Fewer lock acquisition attempts = less load on your lock adapter

**Without Dispatch Logging:**
- Recovery still works but relies solely on distributed locks to prevent duplicates
- Each missed run will attempt to acquire a lock (even if it was already dispatched)
- Still safe, but may cause more lock contention during recovery

### Example Scenarios

**Scenario 1: Short Downtime (< window_lookback)**
- Normal `window_lookback` (120 seconds) handles this automatically
- No special recovery needed

**Scenario 2: Extended Downtime (hours/days)**
- Recovery kicks in on startup
- Looks back 24 hours (default `recovery_window`)
- Re-enqueues all missed runs that should have occurred

**Scenario 3: Cluster Restart**
- All nodes recover simultaneously
- Random jitter (0-5 seconds) staggers recovery attempts
- Distributed locks prevent duplicate enqueues

### Disabling Recovery

To disable automatic recovery (not recommended unless you have a custom solution):

```ruby
RailsCron.configure do |c|
  c.enable_dispatch_recovery = false
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
