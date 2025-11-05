# ⏰ RailsCron — Distributed Cron Scheduler for Rails

> First release 0.1.0 is empty gem.
> A scheduler-agnostic, multi-node-safe cron runner for Ruby and Rails.  
> Designed and maintained by **Codevedas Inc.**

[![Gem](https://img.shields.io/gem/v/rails_cron.svg?style=flat-square)](https://rubygems.org/gems/rails_cron)
[![CI](https://github.com/Code-Vedas/rails_cron/actions/workflows/ci.yml/badge.svg)](https://github.com/Code-Vedas/rails_cron/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/rails_cron/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/rails_cron)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/rails_cron/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/rails_cron)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B-336791?style=flat-square&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-6%2B-d92b2b?style=flat-square&logo=redis&logoColor=white)

---

## 🧭 Project Structure

This repository contains the **RailsCron** gem and its documentation site.

```text

/repo-root
├── .github/              # CI workflows, issue templates
├── rails_cron/           # Gem source (lib/, bin/, gemspec)
├── docs/                 # Documentation site (Jekyll + Markdown)
└── README.md             # This file
```

---

## 🧩 What It Does

`rails_cron` lets you **register, schedule, and safely run recurring tasks** across multiple Rails instances.  
It ensures **exactly-once** dispatching per cron tick using distributed locks via **Redis** or **PostgreSQL advisory locks**.

It’s **scheduler-agnostic** — works with any background job system (`ActiveJob`, `Sidekiq`, `Resque`, etc.)  
and provides a clean Ruby API, CLI, and Rails tasks.

---

## 📚 Documentation

Comprehensive guides are published at:

👉 **[https://rails-cron.codevedas.com](https://rails-cron.codevedas.com)**

| Section                                                            | Description                           |
| ------------------------------------------------------------------ | ------------------------------------- |
| [Overview & Motivation](https://rails-cron.codevedas.com/overview) | Why RailsCron exists                  |
| [Installation & Setup](https://rails-cron.codevedas.com/install)   | Gem setup and initializer             |
| [Usage](https://rails-cron.codevedas.com/usage)                    | Registering jobs, CLI, and Rake tasks |
| [FAQ / Troubleshooting](https://rails-cron.codevedas.com/faq)      | Common issues and fixes               |

---

## 🛠️ Local Development

### 1. Clone and setup

```bash
git clone https://github.com/CodevedasInc/rails-cron.git
cd rails-cron
bundle install
```

### 2. Run specs

```bash
bin/rspec-unit
```

### 3. Lint and format

```bash
bin/rubocop
```

### 4. Reek

```bash
bin/Reek
```

---

## 🧪 Running the Gem Locally

You can load a local version of the gem in a test Rails app:

```bash
gem build rails_cron.gemspec
gem install ./rails_cron-0.1.0.gem
```

Or reference it directly in another app’s `Gemfile`:

```ruby
gem "rails_cron", path: "../rails-cron/rails_cron"
```

---

## 🚀 Docs Site (Jekyll)

The `docs/` directory is a Jekyll site used for GitHub Pages.

### Run locally

```bash
cd docs
bundle install
bundle exec jekyll serve
```

Then open:
👉 [http://localhost:4000](http://localhost:4000)

---

## ⚙️ Continuous Integration

GitHub Actions workflows include:

| Workflow              | Purpose                                           |
| --------------------- | ------------------------------------------------- |
| `ci.yml`              | Runs tests (RSpec + RuboCop) on all Ruby versions |
| `release.yml`         | Builds and publishes gem to RubyGems              |
| `jekyll-gh-pages.yml` | Builds and deploys docs to GitHub Pages           |

---

## Contributing, Security, Conduct

- **Contributing:** see [CONTRIBUTING.md](./CONTRIBUTING.md)
- **Security policy:** see [SECURITY.md](./SECURITY.md)
- **Code of Conduct:** see [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)

---

## 📄 License

Released under the [MIT License](LICENSE)
© 2025 **Codevedas Inc.** — All rights reserved.
