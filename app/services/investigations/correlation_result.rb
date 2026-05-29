module Investigations
  CorrelationResult = Struct.new(:verdict_status, :findings, :suggested_track, keyword_init: true)
end
