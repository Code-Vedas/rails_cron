# ⏰ Kaal

> Kaal is a distributed cron scheduler for Ruby that safely executes scheduled tasks across multiple nodes.

[![Gem](https://img.shields.io/gem/v/kaal.svg?style=flat-square)](https://rubygems.org/gems/kaal)
[![CI](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml/badge.svg)](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/kaal/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B-336791?style=flat-square&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-6%2B-d92b2b?style=flat-square&logo=redis&logoColor=white)

---

## ✨ Overview

`kaal` lets you **bind cron expressions to Ruby code or shell commands** without depending on any specific job system or scheduler.

It guarantees that:

- Each scheduled tick **enqueues work exactly once** across all running Ruby nodes.
- You remain **agnostic** to your background job system (`ActiveJob`, `Sidekiq`, `Resque`, etc.).
- Locks are coordinated safely via **Redis** or **PostgreSQL advisory locks**.
- Cron syntax can be **validated, linted, humanized, and translated** with i18n.

---

## 🧩 Why Kaal?

| Problem                              | Kaal Solution                                         |
| ------------------------------------ | ----------------------------------------------------- |
| Multiple nodes running the same cron | Distributed locks → exactly-once execution            |
| Cron syntax not human-friendly       | Built-in parser + `to_human` translations             |
| Missed runs during downtime          | Configurable _lookback_ window replays missed ticks   |
| Coupled to job system                | Scheduler-agnostic, works with any Ruby queue backend |

---

## ⚙️ Installation

Add to your Gemfile:

```ruby
gem "kaal"
```

Then run:

```bash
bundle install
bin/rails g kaal:install --backend=sqlite
```

The install generator creates `config/initializers/kaal.rb` and, for database-backed backends, generates only the migrations you need:

- `--backend=sqlite`: dispatches, locks, and definitions tables
- `--backend=postgres` or `--backend=mysql`: dispatches and definitions tables
- `--backend=redis` or `--backend=memory`: no database migrations

Example initializer (`config/initializers/kaal.rb`):

```ruby
Kaal.configure do |c|
  # Choose your backend adapter
  # See the Kaal documentation for backend-specific setup and the full
  # configuration reference.
  #
  # Redis (recommended)
  # c.backend = Kaal::Backend::RedisAdapter.new(Redis.new(url: ENV["REDIS_URL"]))

  # or Postgres advisory locks
  # c.backend = Kaal::Backend::PostgresAdapter.new

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

👉 [See full installation guide →](https://kaal.codevedas.com/install)

---

## 🚀 Quick Start

Register a scheduled job anywhere during boot (e.g., `config/initializers/kaal_jobs.rb`):

```ruby
Kaal.register(
  key: "reports:weekly_summary",
  cron: "0 9 * * 1", # every Monday at 9 AM
  enqueue: ->(fire_time:, idempotency_key:) {
    WeeklySummaryJob.perform_later(fire_time: fire_time, key: idempotency_key)
  }
)
```

Start the scheduler:

`Kaal` does **not** auto-start by default. Start it explicitly via `Kaal.start!` or `kaal:start`.

```bash
bundle exec rails kaal:start
```

> 💡 Recommended: run as a **dedicated process** in production (Procfile, systemd, Kubernetes).

---

## 🧰 CLI & Rake Tasks

### CLI Examples

```bash
$ kaal explain "*/15 * * * *"
Every 15 minutes

$ kaal next "0 9 * * 1" --count 3
2025-11-03 09:00:00 UTC
2025-11-10 09:00:00 UTC
2025-11-17 09:00:00 UTC
```

### Rails Tasks

```bash
bin/rails kaal:start          # Start scheduler loop
bin/rails kaal:status         # Show registry & configuration
bin/rails kaal:tick           # Trigger one tick manually
bin/rails kaal:explain["*/5 * * * *"] # Humanize cron expression
```

---

## 🧠 Cron Utilities

```ruby
Kaal.valid?("0 * * * *")     # => true
Kaal.simplify("0 0 * * *")   # => "@daily"
Kaal.lint("*/61 * * * *")    # => ["invalid minute step: 61"]

I18n.locale = :fr
Kaal.to_human("0 9 * * 1")   # => "À 09h00 chaque lundi"
```

> 🈶 All tokens are i18n-based — override translations under `kaal.*` keys.

---

## 🧱 Running the Scheduler

Run the scheduler as a dedicated process in production.  
Do not run it inside web server processes by default.

**Procfile (process manager):**

```procfile
web:       bundle exec puma -C config/puma.rb
scheduler: bundle exec rails kaal:start
```

**systemd unit:**

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

**Kubernetes Deployment:**

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

For Kubernetes, the scheduler process is the container's main process; if it exits, Kubernetes restarts it.  
Do not use `kaal:status` as a liveness/readiness probe for scheduler thread health because it runs in a separate process.

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

📖 [See FAQ →](https://kaal.codevedas.com/faq)

---

## 🧪 Testing Example

```ruby
RSpec.describe "multi-node safety" do
  it "dispatches exactly once across two threads" do
    redis = FakeRedis::Redis.new
    lock  = Kaal::Backend::RedisAdapter.new(redis)
    Kaal.configure { |c| c.backend = lock }

    threads = 2.times.map { Thread.new { Kaal.tick! } }
    threads.each(&:join)

    expect(redis.keys.grep(/dispatch/).size).to eq(1)
  end
end
```

### Local Test Commands

Run the fast unit suite from the gem directory:

```bash
bin/rspec-unit
```

Run end-to-end adapter coverage with the same entrypoint used in CI:

```bash
bin/rspec-e2e memory
bin/rspec-e2e sqlite
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/kaal_test bin/rspec-e2e pg
DATABASE_URL=mysql2://root:rootROOT\!1@127.0.0.1:3306/kaal_test bin/rspec-e2e mysql
REDIS_URL=redis://127.0.0.1:6379/0 bin/rspec-e2e redis
```

`pg` and `mysql` require `DATABASE_URL`. `redis` requires `REDIS_URL`. `memory` and `sqlite` use local test defaults.

---

## 🧩 Roadmap

| Area             | Description                      | Label     |
| ---------------- | -------------------------------- | --------- |
| Registry & API   | Cron registration and validation | `feature` |
| Coordinator Loop | Safe ticking and dispatch        | `feature` |
| Lock Adapters    | Redis / Postgres                 | `build`   |
| CLI Tool         | `kaal` executable                | `build`   |
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

- [Overview & Motivation](https://kaal.codevedas.com)
- [Installation](https://kaal.codevedas.com/install)
- [Usage](https://kaal.codevedas.com/usage)
- [FAQ / Troubleshooting](https://kaal.codevedas.com/faq)

---

## 📄 License

Released under the [MIT License](LICENSE).
© 2025 **Codevedas Inc.** — All rights reserved.
