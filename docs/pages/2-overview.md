---
title: Overview & Motivation
nav_order: 2
permalink: /overview
---

# ⏰ Overview & Motivation

`kaal` exists to solve one persistent problem in distributed Ruby applications:

> **How can you run scheduled tasks safely across multiple nodes — without tying yourself to a specific job system or scheduler?**

Traditional cron jobs or Sidekiq-Cron setups work fine until you scale horizontally.  
Then, the same cron tick may run **N times** where N = number of processes or pods.  
`kaal` eliminates this duplication while staying easy to embed in Rails applications.

---

## 🚀 Why Kaal?

- **Scheduler-agnostic** — No dependency on Sidekiq, Resque, or Rufus; just Ruby and backend adapters.
- **Multi-node safe** — Guarantees _exactly-once_ dispatch even across multiple app instances.
- **Centralized registry** — All crons defined in one place, version-controlled with your code.
- **Redis or Postgres backends** — Choose where lock coordination, cron definitions, and dispatch records are stored.
- **Portable & lightweight** — Runs as a standalone process, Rake task, or inline with Rails.
- **Developer-friendly** — Validate, lint, and simplify cron expressions with clear feedback.

---

## 🧩 Design Principles — Production Ready by Default

- **Deterministic dispatching** — Every cron tick generates an idempotent key.
- **Observability** — Built-in CLI and Rake tasks for introspection and debugging.
- **Resilient to downtime** — Configurable _lookback window_ to replay missed runs.
- **Rails integration** — Uses ActiveJob, `Rails.logger`, and Railtie for smooth application boot.
- **Graceful shutdown** — Completes current tick before exiting on `TERM` or `INT`.
- **Standalone-friendly** — Run as a background process via Procfile, systemd, or Kubernetes.
- **Cron helpers** — Built-in helpers for safe cron authoring workflows.
- **MIT licensed** — Fully open source, with no paid or enterprise tier.

---

## 🧮 Example Performance Snapshot

| Mode                    | Nodes | Lock Adapter | Guarantee           | Overhead (avg ms/tick) |
| ----------------------- | ----- | ------------ | ------------------- | ---------------------- |
| Local (single)          | 1     | Memory       | At-most-once local  | ~0.1                   |
| Redis distributed       | 3     | Redis        | Exactly-once global | ~1.2                   |
| Postgres advisory locks | 3     | Postgres     | Exactly-once global | ~1.8                   |

> These timings were measured with 100 concurrent ticks over a 5-second interval.  
> Both Redis and Postgres adapters maintain sub-2 ms average dispatch overhead.

---

## 💡 When to Use Kaal

- You deploy **multiple web or job nodes** and need **only one node** to enqueue scheduled work.
- You want **one unified registry** for all scheduled tasks, in code — not in crontab files.
- You prefer to **stay job-system agnostic** while maintaining visibility and control.
- You need **validation and linting helpers** while authoring cron schedules.
- You want a **lightweight, zero-dependency** alternative to heavy schedulers.

---

## 📊 Takeaways

- Stop writing `if leader?` logic around cron jobs — `kaal` handles that.
- Run safely in **multi-node environments** (Heroku, Kubernetes, ECS, etc.).
- Use **Redis** for speed, **Postgres** for portability.
- View, test, and run crons entirely from the **CLI or Rails console**.
- Keep everything open, testable, and Ruby-native.

---

> Read next: [Configuration →](/configuration)
