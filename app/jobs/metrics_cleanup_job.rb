class MetricsCleanupJob < ApplicationJob
  queue_as :default

  # Clean up old metrics data to keep database performant
  def perform(retention_days: 30)
    cutoff_date = retention_days.days.ago
    
    Rails.logger.info "Starting metrics cleanup for data older than #{cutoff_date}"
    
    # Count records before cleanup
    total_before = NodeMetric.count
    old_records_count = NodeMetric.where('created_at < ?', cutoff_date).count
    
    Rails.logger.info "Found #{old_records_count} metrics records older than #{retention_days} days (total: #{total_before})"
    
    if old_records_count > 0
      # Delete in batches to avoid long-running transactions
      batch_size = 1000
      deleted_count = 0
      
      loop do
        batch_deleted = NodeMetric.where('created_at < ?', cutoff_date).limit(batch_size).delete_all
        break if batch_deleted == 0
        
        deleted_count += batch_deleted
        Rails.logger.info "Deleted #{batch_deleted} metrics records (total deleted: #{deleted_count})"
        
        # Small pause between batches to avoid overwhelming the database
        sleep(0.1)
      end
      
      total_after = NodeMetric.count
      Rails.logger.info "Metrics cleanup completed. Deleted #{deleted_count} records. Database size reduced from #{total_before} to #{total_after} records."
      
      # Broadcast cleanup completion to development console
      if Rails.env.development?
        console_data = {
          timestamp: Time.current.strftime("%H:%M:%S"),
          event_type: "metrics_cleanup",
          deleted_count: deleted_count,
          retention_days: retention_days,
          total_before: total_before,
          total_after: total_after
        }
        ActionCable.server.broadcast("development_console", console_data)
      end
    else
      Rails.logger.info "No old metrics records found to clean up"
    end
  rescue => e
    Rails.logger.error "Error during metrics cleanup: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end
