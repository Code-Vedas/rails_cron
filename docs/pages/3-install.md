---
title: Installation & Setup
nav_order: 3
permalink: /install
---

# ⚙️ Installation & Setup

This page explains how to install the `rails-crons` gem and set up the initializer for your Rails application.

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

# Generate the initializer
bin/rails g rails_cron:install
```

---

## ⚙️ Initializer

If you ran the generator, you’ll find the file at:

```bash
config/initializers/rails_cron.rb
```

Example:

```ruby
# config/initializers/rails_cron.rb
RailsCron.configure do |c|
  # Choose your distributed lock adapter
  # Redis (recommended)
  # c.lock_adapter = RailsCron::Lock::RedisAdapter.new(Redis.new(url: ENV.fetch("REDIS_URL")))

  # or Postgres advisory locks
  # c.lock_adapter = RailsCron::Lock::PostgresAdapter.new

  # Frequency of scheduler ticks (seconds)
  c.tick_interval    = 5

  # Time window to recover missed runs (seconds)
  c.window_lookback  = 120

  # Lease duration for distributed locks (seconds)
  c.lease_ttl        = 60
end
```

---

## ✅ Verify Installation

You can confirm everything is wired up by running:

```bash
bin/rails rails_cron:status
```

If successful, you’ll see your configuration and the registered cron jobs listed.
