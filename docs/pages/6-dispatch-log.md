---
title: Dispatch Log & Querying History
nav_order: 6
permalink: /dispatch-log
---

# 📋 Dispatch Log & Querying History

When dispatch logging is enabled (`enable_log_dispatch_registry = true`), RailsCron maintains an audit trail of all cron job dispatch attempts. This allows you to query historical dispatch records, debug issues, and perform cleanup operations.

---

## Enabling Dispatch Logging

Configure dispatch logging in your Rails initializer:

```ruby
# config/initializers/rails_cron.rb
RailsCron.configure do |config|
  # Enable audit trail for all cron jobs
  config.enable_log_dispatch_registry = true
  
  # Choose your backend (determines storage and available methods)
  config.lock_adapter = RailsCron::Lock::PostgresAdapter.new
end
```

---

## Accessing the Dispatch Log Registry

Use `RailsCron.dispatch_log_registry` to access the underlying registry instance:

```ruby
registry = RailsCron.dispatch_log_registry

# Returns nil if no adapter is configured or adapter doesn't support dispatch logging
if registry.nil?
  puts "Dispatch logging not configured"
else
  puts "Dispatch registry is available"
end
```

---

## Common API (All Backends)

These methods are available on all dispatch registry backends:

### `find_dispatch(key, fire_time)`

Find a specific dispatch record:

```ruby
registry = RailsCron.dispatch_log_registry
fire_time = Time.at(1609459200)

record = registry.find_dispatch('reports:daily', fire_time)
# => { key: 'reports:daily', fire_time: Time, dispatched_at: Time, node_id: String, status: String }
# => nil if not found
```

### `dispatched?(key, fire_time)`

Check if a dispatch exists (same as `RailsCron.dispatched?` but at registry level):

```ruby
registry = RailsCron.dispatch_log_registry
already_dispatched = registry.dispatched?('reports:daily', Time.current)
# => true or false
```

---

## Database Backend API

When using `RailsCron::Lock::PostgresAdapter`, `RailsCron::Lock::MySQLAdapter`, or `RailsCron::Lock::SQLiteAdapter` adapters, the dispatch registry provides advanced querying:

### `find_by_key(key)`

Find all dispatch records for a specific cron job:

```ruby
registry = RailsCron.dispatch_log_registry

# Get all historical dispatches, most recent first
records = registry.find_by_key('reports:daily')

# ActiveRecord::Relation, so you can chain more conditions
records.where(status: 'dispatched').limit(10)
records.order(fire_time: :asc)
```

### `find_by_node(node_id)`

Find all dispatches originating from a specific node:

```ruby
registry = RailsCron.dispatch_log_registry

# Find all dispatches from a specific worker node
records = registry.find_by_node('web-worker-1')
# Most recent first

# Filter by status
failed = registry.find_by_node('web-worker-1').where(status: 'failed')
```

### `find_by_status(status)`

Find all dispatch records with a specific status:

```ruby
registry = RailsCron.dispatch_log_registry

# Find successful dispatches
dispatched = registry.find_by_status('dispatched')

# Find failed attempts
failed = registry.find_by_status('failed')
```

### `cleanup(recovery_window: 86400)`

Delete old dispatch records to prevent unbounded database growth:

```ruby
registry = RailsCron.dispatch_log_registry

# Delete dispatch records older than 7 days
deleted_count = registry.cleanup(recovery_window: 7 * 24 * 60 * 60)
puts "Deleted #{deleted_count} old dispatch records"

# Default is 24 hours
registry.cleanup  # Deletes records older than 86400 seconds
```

---

## Memory Backend API

When using `RailsCron::Lock::MemoryAdapter` adapter, the registry provides in-memory inspection:

### `clear()`

Clear all dispatch records (useful for testing):

```ruby
registry = RailsCron.dispatch_log_registry

registry.clear  # Removes all dispatches
```

### `size()`

Get the number of stored dispatch records:

```ruby
registry = RailsCron.dispatch_log_registry

count = registry.size
puts "#{count} dispatch records in memory"
```

---

## Redis Backend

When using `RailsCron::Lock::RedisAdapter` adapter, dispatch records are automatically expired based on TTL:

```ruby
# config/initializers/rails_cron.rb
redis = Redis.new(url: ENV['REDIS_URL'])
RailsCron.configure do |config|
  config.lock_adapter = RailsCron::Lock::RedisAdapter.new(redis, namespace: 'myapp')
  config.enable_log_dispatch_registry = true
end

# Redis automatically expires records after 7 days (default TTL)
# No manual cleanup needed
```

---

## Practical Examples

### Example 1: Debug Why a Job Wasn't Enqueued

```ruby
registry = RailsCron.dispatch_log_registry
fire_time = 1.hour.ago.beginning_of_hour

# Check if it was already dispatched
if registry.find_dispatch('sync:data', fire_time)
  puts "Already dispatched, deduplication prevented job enqueue"
  record = registry.find_dispatch('sync:data', fire_time)
  puts "Dispatched at: #{record[:dispatched_at]} from node: #{record[:node_id]}"
else
  puts "No dispatch record found for this fire time"
end
```

### Example 2: Find Recently Failed Dispatches

```ruby
registry = RailsCron.dispatch_log_registry

# Get failed dispatches from the last hour
failed = registry.find_by_key('reports:daily')
                 .where(status: 'failed')
                 .where('dispatched_at >= ?', 1.hour.ago)

failed.each do |record|
  puts "Job #{record.key} failed at #{record.dispatched_at} on node #{record.node_id}"
end
```

### Example 3: Analyze Dispatch Pattern by Node

```ruby
registry = RailsCron.dispatch_log_registry

# Find which nodes dispatch the most jobs
nodes = ['web-1', 'web-2', 'worker-1']

nodes.each do |node_id|
  dispatches = registry.find_by_node(node_id)
  count = dispatches.count
  puts "Node #{node_id}: #{count} dispatches"
end
```

### Example 4: Automated Cleanup Task

Create a recurring task to clean up old dispatch records:

```ruby
# lib/tasks/rails_cron_cleanup.rake
namespace :rails_cron do
  desc 'Clean up old dispatch records'
  task cleanup_dispatch_log: :environment do
    registry = RailsCron.dispatch_log_registry
    
    if registry.nil?
      puts 'Dispatch logging not configured, skipping cleanup'
      next
    end
    
    # Delete records older than 30 days
    recovery_window = 30 * 24 * 60 * 60
    deleted = registry.cleanup(recovery_window: recovery_window)
    puts "Cleaned up #{deleted} dispatch records older than 30 days"
  end
end
```

Then schedule it in your cron system:

```ruby
RailsCron.register(
  key: 'maintenance:cleanup-dispatch-log',
  cron: '0 1 * * *',  # Daily at 1 AM
  enqueue: ->(_fire_time:, **) {
    Rake::Task['rails_cron:cleanup_dispatch_log'].invoke
  }
)
```

---

## Direct Model Access

For advanced queries, you can also query the `RailsCron::CronDispatch` ActiveRecord model directly:

```ruby
# Find all dispatches for a job, ordered by recency
RailsCron::CronDispatch.where(key: 'reports:daily').order(fire_time: :desc)

# Count total dispatches
RailsCron::CronDispatch.count

# Find dispatches from today
RailsCron::CronDispatch.where('fire_time >= ?', Time.current.beginning_of_day)

# Find the most recently dispatched job
RailsCron::CronDispatch.order(dispatched_at: :desc).first
```

**Note:** It's recommended to use `RailsCron.dispatch_log_registry` for consistency, as it properly abstracts the underlying storage backend.

---

## Troubleshooting

### Registry returns `nil`

```ruby
registry = RailsCron.dispatch_log_registry
# => nil

# Check if dispatch logging is enabled
RailsCron.configuration.enable_log_dispatch_registry
# => false

# Check if lock adapter is configured
RailsCron.configuration.lock_adapter
# => nil
```

### Get "method not found" error

```ruby
registry = RailsCron.dispatch_log_registry

# This will fail on Memory backend (doesn't support bulk queries)
registry.find_by_key('mykey')  # Error: Memory backend doesn't have this method
```

**Solution:** Use portable methods available on all backends:

```ruby
# Instead of find_by_key, use find_dispatch in a loop
fire_times = [1.day.ago, 2.days.ago, 3.days.ago]
fire_times.each do |ft|
  record = registry.find_dispatch('mykey', ft)
  # process record
end
```

### Performance Issues with Large Tables

If your dispatch table is very large, consider:

1. **Run cleanup regularly:**
   ```ruby
   RailsCron.dispatch_log_registry.cleanup(recovery_window: 7 * 24 * 60 * 60)
   ```

2. **Use indexed queries:**
   ```ruby
   # Indexed by key, fire_time
   registry.find_dispatch('mykey', Time.current)
   
   # Slower: full table scan
   RailsCron::CronDispatch.where(status: 'failed')
   ```

3. **Archive old records:**
   ```ruby
   # Export records older than 90 days to archive storage
   old = RailsCron::CronDispatch.where('fire_time < ?', 90.days.ago)
   # ... backup to S3, etc ...
   old.delete_all
   ```
