---
layout: default
title: Home
nav_order: 1
---

# Rails Cron (rails_cron)

> First release 0.0.1 is empty gem.

[![Gem](https://img.shields.io/gem/v/rails_cron.svg?style=flat-square)](https://rubygems.org/gems/rails_cron)
[![CI](https://github.com/Code-Vedas/rails_cron/actions/workflows/ci.yml/badge.svg)](https://github.com/Code-Vedas/rails_cron/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/rails_cron/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/rails_cron)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/rails_cron/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/rails_cron)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B-336791?style=flat-square&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-6%2B-d92b2b?style=flat-square&logo=redis&logoColor=white)

> A Rails gem to manage cron jobs in a simple and efficient way that is not tied to any specific background job processor.

- 📦 gem: [`rails_cron/`](https://github.com/Code-Vedas/rails_cron/tree/main/rails_cron)

---

## Install the gem

```ruby
# Gemfile
gem 'rails_cron'
```

```bash
# Install the gem
bundle install

# Generate the initializer and migrations
bin/rails g rails_cron:install
```

## Links

- [Installation & Setup](./install) for how to install the `rails_cron` gem, configure it.
- [Configuration Options](./configuration) for a comprehensive list of configuration options available in the `rails_cron` gem.
- [Usage & Examples](./usage) section for detailed guides on configuring and using the `rails_cron` gem.
- [FAQ / Troubleshooting](./faq) for answers to common questions and troubleshooting tips when working with the `rails_cron` gem.

## Features

- **Scheduler-agnostic**: Works with any job system (`ActiveJob`, `Sidekiq`, `Resque`, etc.)
- **Multi-node safe**: Ensures single-dispatch execution across all app instances
- **Lock adapters**: Redis (`SET NX PX`) and Postgres (`pg_try_advisory_lock`), plus in-memory fallback
- **Registry & API**: Centralized job registration with deterministic idempotency keys
- **Dispatch recovery**: Replays missed runs within a configurable lookback window
- **Cron utilities**: Validate, lint, simplify (`@daily`), humanize, and translate via i18n
- **i18n keys**: Fully localizable weekdays, months, and time phrases (`rails_cron.*`)
- **CLI tools**: `rails-crons explain`, `next`, `run`, and Rails Rake tasks (`rails_cron:start`, `status`, etc.)
- **Standalone mode**: Launch scheduler via Procfile, systemd, or Kubernetes
- **Rails integration**: Railtie auto-loads configuration and Rake tasks
- **Observability**: Optional status inspection via `rails_cron:status`
- **Graceful shutdown**: Handles `TERM`/`INT` signals and finishes current tick cleanly
- **Testing**: Thread-safe, multi-node safety specs included
- **Development & CI**: Bundler, RSpec, RuboCop, GitHub Actions workflows
- **Documentation**: README, feature templates, and roadmap included

---

## Professional support

Need help with integrating or customizing `rails_cron` for your project? We offer professional support and custom development services. Contact us at [sales@codevedas.com](mailto:sales@codevedas.com) for inquiries.

## License

MIT © Codevedas Inc.
