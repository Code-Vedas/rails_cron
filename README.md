# Kaal

> Kaal is a distributed cron scheduler for Ruby that safely executes scheduled tasks across multiple nodes.

[![Gem](https://img.shields.io/gem/v/kaal.svg?style=flat-square)](https://rubygems.org/gems/kaal)
[![CI](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml/badge.svg)](https://github.com/Code-Vedas/kaal/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/Code-Vedas/projects/kaal/maintainability.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
[![Code Coverage](https://qlty.sh/gh/Code-Vedas/projects/kaal/coverage.svg)](https://qlty.sh/gh/Code-Vedas/projects/kaal)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B-336791?style=flat-square&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-6%2B-d92b2b?style=flat-square&logo=redis&logoColor=white)

---

## 🧭 Project Structure

This repository contains the **Kaal** gem and its documentation site.

```text

/repo-root
├── .github/              # CI workflows, issue templates
├── kaal/           # Gem source (lib/, bin/, gemspec)
├── docs/                 # Documentation site (Jekyll + Markdown)
└── README.md             # This file
```

---

## 🧩 What It Does

`kaal` lets you **register, schedule, and safely run recurring tasks** across multiple Ruby nodes.  
It ensures **exactly-once** dispatching per cron tick using distributed locks via **Redis** or **PostgreSQL advisory locks**.

It’s **scheduler-agnostic** and works with any background job system (`ActiveJob`, `Sidekiq`, `Resque`, etc.), while exposing a clean Ruby API, CLI, and Rails integration.

---

## 📚 Documentation

Comprehensive guides are published at:

👉 **[https://kaal.codevedas.com](https://kaal.codevedas.com)**

| Section                                                      | Description                           |
| ------------------------------------------------------------ | ------------------------------------- |
| [Overview & Motivation](https://kaal.codevedas.com/overview) | Why Kaal exists                       |
| [Installation & Setup](https://kaal.codevedas.com/install)   | Gem setup and initializer             |
| [Usage](https://kaal.codevedas.com/usage)                    | Registering jobs, CLI, and Rake tasks |
| [FAQ / Troubleshooting](https://kaal.codevedas.com/faq)      | Common issues and fixes               |

---

## 🛠️ Local Development

### 1. Clone and setup

```bash
git clone https://github.com/CodevedasInc/kaal.git
cd kaal
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
gem build kaal.gemspec
gem install ./kaal-0.1.0.gem
```

Or reference it directly in another app’s `Gemfile`:

```ruby
gem "kaal", path: "../kaal/kaal"
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
