# ⏰ RailsCron

> First release 0.1.0 is empty gem.
> 🕒 A scheduler-agnostic, multi-node-safe cron runner for Ruby and Rails — with Redis or Postgres advisory locks.

[![Gem](https://img.shields.io/gem/v/rails_cron.svg?style=flat-square)](https://rubygems.org/gems/rails_cron)
[![CI](https://github.com/Code-Vedas/rails_cron/actions/workflows/ci.yml/badge.svg)](https://github.com/Code-Vedas/rails_cron/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/rails_cron/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/rails_cron)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/rails_cron/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/rails_cron)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B-336791?style=flat-square&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-6%2B-d92b2b?style=flat-square&logo=redis&logoColor=white)

---

## ✨ Overview

`rails_cron` lets you **bind cron expressions to Ruby code or shell commands** —  
without depending on any specific job system or scheduler (like Sidekiq-Cron or Rufus).

It guarantees that:

- Each scheduled tick **enqueues work exactly once** across all running Ruby nodes.
- You remain **agnostic** to your background job system (`ActiveJob`, `Sidekiq`, `Resque`, etc.).
- Locks are coordinated safely via **Redis** or **PostgreSQL advisory locks**.
- Cron syntax can be **validated, linted, humanized, and translated** with i18n.

---

## 🧩 Why RailsCron?

| Problem                              | RailsCron Solution                                    |
| ------------------------------------ | ----------------------------------------------------- |
| Multiple nodes running the same cron | Distributed locks → exactly-once execution            |
| Cron syntax not human-friendly       | Built-in parser + `to_human` translations             |
| Missed runs during downtime          | Configurable _lookback_ window replays missed ticks   |
| Coupled to job system                | Scheduler-agnostic, works with any Ruby queue backend |

---

## ⚙️ Installation

Add to your Gemfile:

```ruby
gem "rails_cron"
```

Then run:

```bash
bundle install
bin/rails g rails_cron:install --backend=sqlite
```

The install generator creates `config/initializers/rails_cron.rb` and, for database-backed backends, generates only the migrations you need:

- `--backend=sqlite`: dispatches, locks, and definitions tables
- `--backend=postgres` or `--backend=mysql`: dispatches and definitions tables
- `--backend=redis` or `--backend=memory`: no database migrations

Example initializer (`config/initializers/rails_cron.rb`):

```ruby
RailsCron.configure do |c|
  # Choose your backend adapter
  # See the RailsCron documentation for backend-specific setup and the full
  # configuration reference.
  #
  # Redis (recommended)
  # c.backend = RailsCron::Backend::RedisAdapter.new(Redis.new(url: ENV["REDIS_URL"]))

  # or Postgres advisory locks
  # c.backend = RailsCron::Backend::PostgresAdapter.new

  c.tick_interval    = 5      # seconds between scheduler ticks
  c.window_lookback  = 120    # recover missed runs (seconds)
  c.lease_ttl        = 125    # must be >= window_lookback + tick_interval
  c.recovery_window = 3600
  c.enable_dispatch_recovery = true
  c.enable_log_dispatch_registry = false

  # Scheduler file loading
  c.scheduler_config_path = "config/scheduler.yml"
  c.scheduler_conflict_policy = :error # :error, :code_wins, :file_wins
  c.scheduler_missing_file_policy = :warn # :warn, :error
end
```

Example scheduler file (`config/scheduler.yml`):

```yaml
defaults:
  jobs:
    - key: "reports:weekly_summary"
      cron: "0 9 * * 1"
      job_class: "WeeklySummaryJob"
      enabled: true
      queue: "default"
      args:
        - "{{fire_time.iso8601}}"
      kwargs:
        idempotency_key: "{{idempotency_key}}"
      metadata:
        owner: "ops"

production:
  jobs:
    - key: "reports:daily_digest"
      cron: "<%= ENV.fetch('DAILY_DIGEST_CRON', '0 7 * * *') %>"
      job_class: "DailyDigestJob"
```

`scheduler.yml` supports ERB and environment sections (`defaults`, `development`, `test`, `production`, etc.).
Allowed runtime placeholders in `args` and `kwargs` values (not keys): `{{fire_time.iso8601}}`, `{{fire_time.unix}}`, `{{idempotency_key}}`, `{{key}}`.

👉 [See full installation guide →](https://rails-cron.codevedas.com/install)

---

## 🚀 Quick Start

Register a scheduled job anywhere during boot (e.g., `config/initializers/rails_cron_jobs.rb`):

```ruby
RailsCron.register(
  key: "reports:weekly_summary",
  cron: "0 9 * * 1", # every Monday at 9 AM
  enqueue: ->(fire_time:, idempotency_key:) {
    WeeklySummaryJob.perform_later(fire_time: fire_time, key: idempotency_key)
  }
)
```

Start the scheduler:

`RailsCron` does **not** auto-start by default. Start it explicitly via `RailsCron.start!` or `rails_cron:start`.

```bash
bundle exec rails rails_cron:start
```

> 💡 Recommended: run as a **dedicated process** in production (Procfile, systemd, Kubernetes).

---

## 🧰 CLI & Rake Tasks

### CLI Examples

```bash
$ rails-cron explain "*/15 * * * *"
Every 15 minutes

$ rails-cron next "0 9 * * 1" --count 3
2025-11-03 09:00:00 UTC
2025-11-10 09:00:00 UTC
2025-11-17 09:00:00 UTC
```

### Rails Tasks

```bash
bin/rails rails_cron:start          # Start scheduler loop
bin/rails rails_cron:status         # Show registry & configuration
bin/rails rails_cron:tick           # Trigger one tick manually
bin/rails rails_cron:explain["*/5 * * * *"] # Humanize cron expression
```

---

## 🧠 Cron Utilities

```ruby
RailsCron.valid?("0 * * * *")     # => true
RailsCron.simplify("0 0 * * *")   # => "@daily"
RailsCron.lint("*/61 * * * *")    # => ["invalid minute step: 61"]

I18n.locale = :fr
RailsCron.to_human("0 9 * * 1")   # => "À 09h00 chaque lundi"
```

> 🈶 All tokens are i18n-based — override translations under `rails_cron.*` keys.

---

## 🧱 Running the Scheduler

Run the scheduler as a dedicated process in production.  
Do not run it inside web server processes by default.

**Procfile (process manager):**

```procfile
web:       bundle exec puma -C config/puma.rb
scheduler: bundle exec rails rails_cron:start
```

**systemd unit:**

```ini
[Unit]
Description=RailsCron scheduler
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/apps/myapp/current
Environment=RAILS_ENV=production
ExecStart=/usr/bin/bash -lc 'bundle exec rails rails_cron:start'
ExecStartPre=/usr/bin/bash -lc 'bundle exec rails rails_cron:status'
ExecReload=/bin/kill -TERM $MAINPID
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Kubernetes Deployment:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rails-cron-scheduler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rails-cron-scheduler
  template:
    metadata:
      labels:
        app: rails-cron-scheduler
    spec:
      containers:
        - name: scheduler
          image: your-app:latest
          command: ["bash", "-lc", "bundle exec rails rails_cron:start"]
```

For Kubernetes, the scheduler process is the container's main process; if it exits, Kubernetes restarts it.  
Do not use `rails_cron:status` as a liveness/readiness probe for scheduler thread health because it runs in a separate process.

Use one of these for health checks:

- Process-level checks from your runtime/supervisor for the main scheduler process.
- A shared heartbeat/lease signal (Redis, Postgres, pidfile, etc.) written by the scheduler and read by probes.

---

## 🔍 Troubleshooting

| Symptom                    | Likely Cause          | Fix                                      |
| -------------------------- | --------------------- | ---------------------------------------- |
| Jobs run multiple times    | Using memory lock     | Use Redis or Postgres adapter            |
| Missed jobs after downtime | Short lookback window | Increase `window_lookback`               |
| Scheduler exits early      | Normal SIGTERM        | Exits gracefully after tick              |
| Redis timeout              | Network latency       | Increase Redis timeout or switch adapter |

📖 [See FAQ →](https://rails-cron.codevedas.com/faq)

---

## 🧪 Testing Example

```ruby
RSpec.describe "multi-node safety" do
  it "dispatches exactly once across two threads" do
    redis = FakeRedis::Redis.new
    lock  = RailsCron::Backend::RedisAdapter.new(redis)
    RailsCron.configure { |c| c.backend = lock }

    threads = 2.times.map { Thread.new { RailsCron.tick! } }
    threads.each(&:join)

    expect(redis.keys.grep(/dispatch/).size).to eq(1)
  end
end
```

---

## 🧩 Roadmap

| Area             | Description                      | Label     |
| ---------------- | -------------------------------- | --------- |
| Registry & API   | Cron registration and validation | `feature` |
| Coordinator Loop | Safe ticking and dispatch        | `feature` |
| Lock Adapters    | Redis / Postgres                 | `build`   |
| CLI Tool         | `rails-cron` executable          | `build`   |
| i18n Humanizer   | Multi-language support           | `lang`    |
| Docs & Examples  | Developer onboarding             | `lang`    |

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Run tests (`bundle exec rspec`)
4. Open a PR using the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.md)

Labels: `feature`, `build`, `ci`, `lang`

---

## 📚 Documentation

- [Overview & Motivation](https://rails-cron.codevedas.com)
- [Installation](https://rails-cron.codevedas.com/install)
- [Usage](https://rails-cron.codevedas.com/usage)
- [FAQ / Troubleshooting](https://rails-cron.codevedas.com/faq)

---

## 📄 License

Released under the [MIT License](LICENSE).
© 2025 **Codevedas Inc.** — All rights reserved.
