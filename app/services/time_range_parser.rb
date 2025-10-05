# frozen_string_literal: true

# Service for parsing time range parameters into start times
class TimeRangeParser
  VALID_RANGES = {
    "15m" => 15.minutes,
    "1h" => 1.hour,
    "6h" => 6.hours,
    "24h" => 24.hours,
    "7d" => 7.days
  }.freeze

  DEFAULT_RANGE = "1h"

  def initialize(range_param)
    @range_param = range_param.to_s.presence || DEFAULT_RANGE
  end

  def start_time
    duration = VALID_RANGES[@range_param] || VALID_RANGES[DEFAULT_RANGE]
    duration.ago
  end

  def range
    @range_param
  end

  def valid?
    VALID_RANGES.key?(@range_param)
  end

  class << self
    def parse(range_param)
      new(range_param).start_time
    end

    def valid_ranges
      VALID_RANGES.keys
    end
  end
end
