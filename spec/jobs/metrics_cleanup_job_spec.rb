require 'rails_helper'

RSpec.describe MetricsCleanupJob, type: :job do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

  describe '#perform' do
    let!(:old_metrics) do
      [
        create(:node_metric, node: node, created_at: 35.days.ago),
        create(:node_metric, node: node, created_at: 40.days.ago),
        create(:node_metric, node: node, created_at: 50.days.ago)
      ]
    end

    let!(:recent_metrics) do
      [
        create(:node_metric, node: node, created_at: 1.day.ago),
        create(:node_metric, node: node, created_at: 1.week.ago),
        create(:node_metric, node: node, created_at: 2.weeks.ago)
      ]
    end

    context 'with default retention period (30 days)' do
      it 'deletes metrics older than 30 days' do
        expect {
          MetricsCleanupJob.perform_now
        }.to change { NodeMetric.count }.by(-3)

        # Old metrics should be deleted
        old_metrics.each do |metric|
          expect { metric.reload }.to raise_error(ActiveRecord::RecordNotFound)
        end

        # Recent metrics should remain
        recent_metrics.each do |metric|
          expect { metric.reload }.not_to raise_error
        end
      end

      it 'logs cleanup information' do
        expect(Rails.logger).to receive(:info).with(/Starting metrics cleanup/)
        expect(Rails.logger).to receive(:info).with(/Found 3 metrics records older than 30 days/)
        expect(Rails.logger).to receive(:info).with(/Metrics cleanup completed/)

        MetricsCleanupJob.perform_now
      end
    end

    context 'with custom retention period' do
      it 'deletes metrics older than specified days' do
        expect {
          MetricsCleanupJob.perform_now(retention_days: 7)
        }.to change { NodeMetric.count }.by(-4) # 3 old + 1 recent (1 week old)

        # Only very recent metrics should remain
        expect(NodeMetric.count).to eq(2)
      end
    end

    context 'when no old metrics exist' do
      before do
        NodeMetric.where('created_at < ?', 30.days.ago).delete_all
      end

      it 'does not delete any records' do
        expect {
          MetricsCleanupJob.perform_now
        }.not_to change { NodeMetric.count }
      end

      it 'logs that no cleanup was needed' do
        expect(Rails.logger).to receive(:info).with(/No old metrics records found to clean up/)
        MetricsCleanupJob.perform_now
      end
    end

    context 'with large number of old metrics' do
      before do
        # Create 2500 old metrics to test batch processing
        metrics_data = []
        2500.times do |i|
          metrics_data << {
            node_id: node.id,
            collected_at: 35.days.ago,
            cpu_usage_percent: 50.0,
            memory_total_mb: 8192,
            memory_used_mb: 4096,
            memory_available_mb: 4096,
            uptime_seconds: 86400,
            created_at: 35.days.ago,
            updated_at: 35.days.ago
          }
        end
        NodeMetric.insert_all(metrics_data)
      end

      it 'deletes records in batches' do
        expect(Rails.logger).to receive(:info).with(/Deleted \d+ metrics records/).at_least(3).times
        
        expect {
          MetricsCleanupJob.perform_now
        }.to change { NodeMetric.count }.by(-2500)
      end

      it 'includes batch progress logging' do
        expect(Rails.logger).to receive(:info).with(/total deleted: \d+/).at_least(3).times
        MetricsCleanupJob.perform_now
      end
    end

    context 'in development environment' do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
      end

      it 'broadcasts cleanup completion to development console' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "development_console",
          hash_including(
            event_type: "metrics_cleanup",
            deleted_count: 3,
            retention_days: 30
          )
        )

        MetricsCleanupJob.perform_now
      end
    end

    context 'in production environment' do
      before do
        allow(Rails.env).to receive(:development?).and_return(false)
      end

      it 'does not broadcast to development console' do
        expect(ActionCable.server).not_to receive(:broadcast)
        MetricsCleanupJob.perform_now
      end
    end

    context 'when an error occurs' do
      before do
        allow(NodeMetric).to receive(:where).and_raise(StandardError.new("Database error"))
      end

      it 'logs the error and re-raises it' do
        expect(Rails.logger).to receive(:error).with(/Error during metrics cleanup: Database error/)
        expect(Rails.logger).to receive(:error).with(/.*/)  # backtrace

        expect {
          MetricsCleanupJob.perform_now
        }.to raise_error(StandardError, "Database error")
      end
    end

    context 'with different retention periods' do
      it 'respects 7-day retention' do
        create(:node_metric, node: node, created_at: 8.days.ago)
        create(:node_metric, node: node, created_at: 6.days.ago)

        expect {
          MetricsCleanupJob.perform_now(retention_days: 7)
        }.to change { NodeMetric.count }.by(-4) # 3 old + 1 from 8 days ago
      end

      it 'respects 60-day retention' do
        create(:node_metric, node: node, created_at: 65.days.ago)
        create(:node_metric, node: node, created_at: 55.days.ago)

        expect {
          MetricsCleanupJob.perform_now(retention_days: 60)
        }.to change { NodeMetric.count }.by(-2) # Only the 65-day old one
      end
    end

    context 'performance considerations' do
      it 'includes sleep between batches' do
        # Create enough records to trigger multiple batches
        1500.times do
          create(:node_metric, node: node, created_at: 35.days.ago)
        end

        expect_any_instance_of(MetricsCleanupJob).to receive(:sleep).with(0.1).at_least(1).times
        MetricsCleanupJob.perform_now
      end
    end
  end

  describe 'job configuration' do
    it 'is configured to run on the default queue' do
      expect(MetricsCleanupJob.queue_name).to eq('default')
    end

    it 'inherits from ApplicationJob' do
      expect(MetricsCleanupJob.superclass).to eq(ApplicationJob)
    end
  end

  describe 'integration with recurring jobs' do
    it 'can be scheduled with proper arguments' do
      expect {
        MetricsCleanupJob.perform_later(retention_days: 30)
      }.to have_enqueued_job(MetricsCleanupJob).with(retention_days: 30)
    end
  end
end
