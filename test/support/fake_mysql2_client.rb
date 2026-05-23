# Stand-in for Mysql2::Client used by SQL tests so we never touch a real DB.
# Records every call and lets tests script return values / errors per-query.
class FakeMysql2Client
  attr_reader :init_opts, :queries, :closed

  class << self
    attr_accessor :next_error, :next_result, :instances

    def reset!
      @next_error  = nil
      @next_result = nil
      @instances   = []
    end
  end

  def initialize(opts)
    @init_opts = opts
    @queries   = []
    @closed    = false
    raise self.class.next_error if self.class.next_error && opts[:trigger_init_error]
    (self.class.instances ||= []) << self
  end

  def query(sql, _opts = {})
    @queries << sql
    raise self.class.next_error if self.class.next_error
    self.class.next_result || []
  end

  def close
    @closed = true
  end
end
