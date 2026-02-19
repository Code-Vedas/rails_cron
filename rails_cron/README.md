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
bin/rails g rails_cron:install
```

Example initializer (`config/initializers/rails_cron.rb`):

```ruby
RailsCron.configure do |c|
  # Choose your distributed lock adapter
  # Redis (recommended)
  # c.lock_adapter = RailsCron::Lock::RedisAdapter.new(Redis.new(url: ENV["REDIS_URL"]))

  # or Postgres advisory locks
  # c.lock_adapter = RailsCron::Lock::PostgresAdapter.new

  c.tick_interval    = 5      # seconds between scheduler ticks
  c.window_lookback  = 120    # recover missed runs (seconds)
  c.lease_ttl        = 60     # lock TTL in seconds
end
```

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

**Procfile (Heroku / Foreman):**

```procfile
web:       bundle exec puma -C config/puma.rb
scheduler: bundle exec rails rails_cron:start
```

**systemd unit:**

```ini
[Service]
Type=simple
WorkingDirectory=/var/apps/myapp/current
ExecStart=/usr/bin/bash -lc 'bundle exec rails rails_cron:start'
Restart=always
```

**Kubernetes Deployment:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rails-cron
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: scheduler
          image: your-app:latest
          command: ["bash", "-lc", "bundle exec rails rails_cron:start"]
```

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
    lock  = RailsCron::Lock::RedisAdapter.new(redis)
    RailsCron.configure { |c| c.lock_adapter = lock }

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
