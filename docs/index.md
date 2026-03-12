---
layout: default
title: Home
nav_order: 1
---

# Kaal

> Kaal is a distributed cron scheduler for Ruby that safely executes scheduled tasks across multiple nodes.

[![Gem](https://img.shields.io/gem/v/kaal.svg?style=flat-square)](https://rubygems.org/gems/kaal)
[![CI](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml/badge.svg)](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/kaal/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B-336791?style=flat-square&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-6%2B-d92b2b?style=flat-square&logo=redis&logoColor=white)

- 📦 gem: [`kaal/`](https://github.com/Code-Vedas/kaal/tree/main/kaal)

---

## Install the gem

```ruby
# Gemfile
gem 'kaal'
```

```bash
# Install the gem
bundle install

# Generate the initializer and migrations
bin/rails g kaal:install
```

## Links

- [Installation & Setup](./install) for how to install the `kaal` gem, configure it.
- [Configuration Options](./configuration) for a comprehensive list of configuration options available in the `kaal` gem.
- [Usage & Examples](./usage) section for detailed guides on configuring and using the `kaal` gem.
- [FAQ / Troubleshooting](./faq) for answers to common questions and troubleshooting tips when working with the `kaal` gem.

## Features

- **Scheduler-agnostic**: Works with any job system (`ActiveJob`, `Sidekiq`, `Resque`, etc.)
- **Multi-node safe**: Ensures single-dispatch execution across all app instances
- **Backend adapters**: Redis and Postgres (with in-memory fallback) persist lock coordination, cron definitions, and dispatch records
- **Registry & API**: Centralized job registration with deterministic idempotency keys
- **Dispatch recovery**: Replays missed runs within a configurable lookback window
- **Cron utilities**: Validate, lint, simplify, and humanize via `Kaal.valid?`, `Kaal.lint`, `Kaal.simplify`, and `Kaal.to_human`
- **i18n keys**: Fully localizable weekdays, months, and time phrases (`kaal.*`)
- **CLI tools**: `kaal explain`, `next`, `run`, and Rails Rake tasks (`kaal:start`, `status`, etc.)
- **Standalone mode**: Launch scheduler via Procfile, systemd, or Kubernetes
- **Rails integration**: Railtie auto-loads configuration and Rake tasks
- **Observability**: Optional status inspection via `kaal:status`
- **Graceful shutdown**: Handles `TERM`/`INT` signals and finishes current tick cleanly
- **Testing**: Thread-safe, multi-node safety specs included
- **Development & CI**: Bundler, RSpec, RuboCop, GitHub Actions workflows
- **Documentation**: README, feature templates, and roadmap included

---

## Professional support

Need help with integrating or customizing `kaal` for your project? We offer professional support and custom development services. Contact us at [sales@codevedas.com](mailto:sales@codevedas.com) for inquiries.

## License

MIT © Codevedas Inc.
