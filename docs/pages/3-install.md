---
title: Installation & Setup
nav_order: 3
permalink: /install
---

# ⚙️ Installation & Setup

This page explains how to install the `rails-crons` gem, generate any backend-specific database migrations, and set up the initializer for your Rails application.

---

## 📦 Install

Add to your Gemfile:

```ruby
# Gemfile
gem "rails-crons"
```

Then run:

```bash
# Install the gem
bundle install

# Generate the initializer and any backend-specific migrations
bin/rails g rails_cron:install --backend=sqlite
```

Use the backend option that matches your deployment:

- `--backend=sqlite`: generates dispatches, locks, and definitions tables
- `--backend=postgres` or `--backend=mysql`: generates dispatches and definitions tables
- `--backend=redis` or `--backend=memory`: no database migrations are generated

For database-backed backends, run your app migrations after generating them:

```bash
bin/rails db:migrate
```

---

## ⚙️ Initializer

If you ran the generator, you will find the initializer at:

```bash
config/initializers/rails_cron.rb
```

Example:

```ruby
# config/initializers/rails_cron.rb
RailsCron.configure do |c|
  # Choose the backend that matches your deployment.
  # See the RailsCron documentation for backend-specific setup and the full
  # configuration reference.
  #
  # Redis (recommended)
  # c.backend = RailsCron::Backend::RedisAdapter.new(Redis.new(url: ENV.fetch("REDIS_URL")))

  # or Postgres advisory locks
  # c.backend = RailsCron::Backend::PostgresAdapter.new

  # Frequency of scheduler ticks (seconds)
  c.tick_interval    = 5

  # Time window to recover missed runs (seconds)
  c.window_lookback  = 120

  # Lease duration for distributed coordination (seconds)
  # Keep this >= window_lookback + tick_interval to prevent duplicate dispatch.
  c.lease_ttl        = 125

  # Startup recovery window (seconds)
  c.recovery_window = 3600

  # Recover missed runs on startup
  c.enable_dispatch_recovery = true

  # Persist dispatch records for recovery/idempotency checks
  c.enable_log_dispatch_registry = false
end
```

---

## ✅ Verify Installation

You can confirm everything is wired up by running:

```bash
bin/rails rails_cron:status
```

If successful, you’ll see your configuration and the registered cron jobs listed.
