---
title: Idempotency & Best Practices
nav_order: 7
permalink: /idempotency-best-practices
---

# 🔐 Idempotency & Job Deduplication

Every time Kaal fires a scheduled job, it provides a deterministic **idempotency_key** that uniquely identifies that job execution. This key is designed to help you implement deduplication logic in your job queue system, preventing duplicate job enqueues in distributed systems.

---

## How Idempotency Works

Each cron job receives:

- **`fire_time`**: The time the job was scheduled to run (in your application's configured timezone)
- **`idempotency_key`**: A deterministic key based on namespace, job key, and fire time

The idempotency key is generated as: `{namespace}-{job_key}-{fire_time.to_i}`

```ruby
# Example idempotency_key for namespace='railscron', key='reports:daily', fire_time=1609459200
# => "railscron-reports:daily-1609459200"
```

This deterministic format ensures that:

- The same scheduled job always generates the same key
- Different fire times generate different keys
- Keys are suitable for use as deduplication identifiers

**Note on Timezones:** The `fire_time` object is created in your application's configured timezone (set via `Time.zone` in Rails).
The idempotency key uses `fire_time.to_i` which converts to a Unix timestamp—a timezone-agnostic representation—ensuring consistent key generation regardless of timezone configuration.
However, if you manually create `fire_time` objects for manual idempotency checking, ensure they're created with `Time.current` (which respects your app's timezone) rather than `Time.now` (which uses system timezone).

---

## Using with Job Queues

### Pattern 1: With Dispatch Registry (Recommended for audit trail)

Enable dispatch logging and check before enqueueing:

```ruby
# config/initializers/kaal.rb
Kaal.configure do |config|
  config.enable_log_dispatch_registry = true
end
```

Then use the simple helper in your enqueue callback:

```ruby
Kaal.register(
  key: 'reports:daily',
  cron: '0 9 * * *',
  enqueue: ->(fire_time:, idempotency_key:) {
    return if Kaal.dispatched?('reports:daily', fire_time)

    DailyReportJob.perform_later(fire_time: fire_time, idempotency_key: idempotency_key)
  }
)
```

**Benefits:**

- One-liner deduplication check
- Built-in audit trail of all dispatches
- Works with any job queue system
- Audit trail queryable via `Kaal::CronDispatch` model when enabled

---

### Pattern 2: Custom Deduplication Store (Redis)

Use Redis directly for faster deduplication with custom TTL:

```ruby
# At the top level (e.g., in an initializer)
require 'connection_pool'

REDIS_POOL = ConnectionPool.new(size: 5) { Redis.new(url: ENV['REDIS_URL']) }

Kaal.configure do |config|
  # Pass the ConnectionPool directly to the adapter
  # The pool will check out connections as needed for each lock operation
  config.backend = Kaal::Backend::RedisAdapter.new(REDIS_POOL)
  # Note: enable_log_dispatch_registry can be false - deduplication happens in Redis
end

Kaal.register(
  key: 'sync:data',
  cron: '*/30 * * * *',
  enqueue: ->(fire_time:, idempotency_key:) {
    # In the enqueue callback, also use the pool with .with blocks
    # This ensures connections are properly managed for dispatch registry operations
    REDIS_POOL.with do |redis|
      redis_key = "railscron:dedup:#{idempotency_key}"
      # Use exists? for boolean check (redis-rb 4.2.0+)
      # exists? returns boolean, exists returns integer count
      unless redis.exists?(redis_key)
        redis.setex(redis_key, 24.hours.to_i, true)
        DataSyncJob.perform_later(fire_time: fire_time, idempotency_key: idempotency_key)
      end
    end
  }
)
```

**Benefits:**

- Full control over deduplication logic
- Fast in-memory lookups with Redis
- Custom TTL windows per job type
- Works across multiple app instances
- **Connection pooling for both lease coordination operations and dispatch registry** - connections checked out and released as needed
- No connection exhaustion in production

**How it Works:**

The `ConnectionPool` object delegates all method calls (like `:set`, `:eval`, `:exists?`) to its underlying Redis instances. When the adapter or dispatch registry code calls a method on the pool, it:

1. Checks out a connection from the pool
2. Executes the method on that connection
3. Returns the connection to the pool for reuse

This prevents holding a single connection for the entire application lifetime, allowing the pool to distribute load across multiple connections available in the configured size.

---

### Pattern 3: In-Memory (Development/Testing)

For development and testing, use the memory adapter:

```ruby
  Kaal.configure do |config|
    config.backend = Kaal::Backend::MemoryAdapter.new
    config.enable_log_dispatch_registry = true  # Optional: audit trail in-memory
  end

  Kaal.register(
    key: 'test:job',
    cron: '0 * * * *',
    enqueue: ->(fire_time:, idempotency_key:) {
      return if Kaal.dispatched?('test:job', fire_time)
      TestJob.perform_later(fire_time: fire_time, idempotency_key: idempotency_key)
    }
  )
```

**Benefits:**

- Zero setup required - works in-memory
- Perfect for development and test environments
- Easy deduplication with built-in dispatch registry
- No external dependencies

### Pattern 4: Hybrid (Performance + Audit Trail)

Combine cache checking with dispatch registry for production:

```ruby
  Kaal.configure do |config|
    config.backend = Kaal::Backend::PostgresAdapter.new
    config.enable_log_dispatch_registry = true  # Enable audit trail
  end

  Kaal.register(
    key: 'cleanup:stale',
    cron: '0 2 * * *',
    enqueue: ->(fire_time:, idempotency_key:) {
      # Fast path: check in-memory cache first
      cache_key = "railscron:#{idempotency_key}"
      return if Rails.cache.exist?(cache_key)

      # Slow path: check database dispatch registry (auditable)
      return if Kaal.dispatched?('cleanup:stale', fire_time)

      # Safe to enqueue
      CleanupJob.perform_later(fire_time: fire_time, idempotency_key: idempotency_key)
      Rails.cache.write(cache_key, true, expires_in: 24.hours)
    }
  )
```

**Benefits:**

- Cache hit optimization (most duplicates caught fast)
- Full audit trail for compliance and debugging
- Best for high-volume production crons

---

## Advanced: Using the Helper

For utilities or advanced use cases, use the `with_idempotency` helper:

```ruby
  # Generate an idempotency_key outside of normal job dispatch
  Kaal.with_idempotency('reports:daily', Time.current) do |idempotency_key|
    # Use the key for deduplication in your custom logic
    MyCustomQueue.add(idempotency_key, job_data)
  end
```

---

## Checking Dispatch Status

Use `Kaal.dispatched?` to check if a job has been dispatched:

```ruby
  # Check if a job was already dispatched for a specific fire time
  fire_time = Time.current
  already_dispatched = Kaal.dispatched?('reports:daily', fire_time)

  # Use in your enqueue callback
  Kaal.register(
    key: 'reports:daily',
    cron: '0 9 * * *',
    enqueue: ->(fire_time:, idempotency_key:) {
      if Kaal.dispatched?('reports:daily', fire_time)
        Rails.logger.info("Job already dispatched for fire_time=#{fire_time}")
        return
      end

      DailyReportJob.perform_later(fire_time: fire_time, idempotency_key: idempotency_key)
    }
  )
```

**Note:** If you enabled `enable_log_dispatch_registry`, the dispatches are recorded in the `kaal_dispatches` table and can be queried directly via the CronDispatch model for audit trail purposes. However, the recommended way to check deduplication status is always through `Kaal.dispatched?` helper.

**Important:** When manually checking dispatch status outside the enqueue callback, always use `Time.current` (not `Time.now`) to ensure the fire_time is created in your application's configured timezone, matching how Kaal generates fire_time internally.

---

## Best Practices

✅ **DO:**

- Pass `idempotency_key` when enqueuing jobs
- Store the idempotency_key in your job arguments for debugging
- Log deduplication decisions for observability
- Test your deduplication implementation before production
- Always use `Time.current` when manually creating fire_time objects (not `Time.now`), to ensure timezone consistency

❌ **DON'T:**

- Assume job queues deduplicate automatically (test your setup)
- Ignore the idempotency_key in your enqueue callback
- Use non-deterministic keys (they won't deduplicate properly)
- Forget to set appropriate TTL windows for your deduplication store
- Use `Time.now` in deduplication checks—use `Time.current` instead to respect your app's timezone

---

### Troubleshooting

#### Jobs are being duplicated

1. Verify dispatch logging is enabled:

   ```ruby
   Kaal.configuration.enable_log_dispatch_registry  # Should be true
   ```

2. Check if jobs are actually being logged:

   ```ruby
   # Query the dispatch audit trail directly
   Kaal::CronDispatch.where(key: 'reports:daily')
   ```

3. Verify the deduplication check is working:

   ```ruby
   # Test manually
   fire_time = Time.current
   Kaal.dispatched?('reports:daily', fire_time)  # Should be false first time
   ```

#### Dispatch registry is not recording

1. Verify dispatch logging is enabled:

   ```ruby
   Kaal.configuration.enable_log_dispatch_registry  # Should be true
   ```

2. Verify your backend adapter supports dispatch logging:
   - **DatabaseEngine** (MySQL, PostgreSQL, SQLite): Requires `kaal_dispatches` table
     - Run migrations: `rails db:migrate` (migrations are installed in your host Rails app)
     - Check table: `ActiveRecord::Base.connection.table_exists?('kaal_dispatches')`
   - **RedisEngine**: Requires Redis to be running and accessible
   - **MemoryEngine**: Works out of the box (persists only during process lifetime)

3. Check your adapter configuration:

##### Example: Database adapter

```ruby
  Kaal.configure do |config|
    config.backend = Kaal::Backend::PostgresAdapter.new
    config.enable_log_dispatch_registry = true
  end
```

##### Example: Redis adapter

```ruby
  Kaal.configure do |config|
    redis = Redis.new(url: ENV['REDIS_URL'])
    config.backend = Kaal::Backend::RedisAdapter.new(redis)
    config.enable_log_dispatch_registry = true
  end
```

##### Example: Memory adapter (development/testing only)

```ruby
  Kaal.configure do |config|
    config.backend = Kaal::Backend::MemoryAdapter.new
    config.enable_log_dispatch_registry = true
  end
```

#### All jobs showing as duplicate

1. Verify dispatch logging is enabled and configured correctly:

   ```ruby
     Kaal.configuration.enable_log_dispatch_registry  # Should be true
   ```

2. If using a database backend (MySQL, PostgreSQL, SQLite):
   - Confirm the migration has been applied: `rails db:migrate`
   - Verify the table exists:

   ```ruby
     ActiveRecord::Base.connection.table_exists?('kaal_dispatches')  # Should be true
   ```

3. If using Redis backend:
   - Verify Redis is running and accessible:

   ```ruby
    redis = Redis.new(url: ENV['REDIS_URL'])
    redis.ping  # Should return "PONG"
   ```

4. Verify the fire_time is being set correctly in your enqueue callback:

   ```ruby
   # In your enqueue callback, add debug logging
   Kaal.register(
     key: 'test:job',
     cron: '0 * * * *',
     enqueue: ->(fire_time:, idempotency_key:) {
       puts "fire_time: #{fire_time}, fire_time.class: #{fire_time.class}"
       puts "idempotency_key: #{idempotency_key}"
     }
   )
   ```

#### Timezone Mismatch Issues

If you're manually checking dispatch status using `Kaal.dispatched?`, ensure timezone consistency:

```ruby
# ❌ WRONG - uses system timezone (Time.now)
time_in_system_tz = Time.now
Kaal.dispatched?('job:key', time_in_system_tz)

# ✅ CORRECT - uses app's configured timezone (Time.current)
time_in_app_tz = Time.current
Kaal.dispatched?('job:key', time_in_app_tz)
```

**Why:** Kaal generates fire_times using `Time.current` (your app's configured timezone). When you manually check dispatch status, use the same `Time.current` to ensure the fire_time matches what Kaal expects.

**Check your app's timezone:**

```ruby
Time.zone                # => #<ActiveSupport::TimeZone:0x00... @name="UTC">
Time.current.zone        # => "UTC" (or whatever you configured)
```
