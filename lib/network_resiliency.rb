require "network_resiliency/stats"
require "network_resiliency/stats_engine"
require "network_resiliency/version"

module NetworkResiliency
  module Adapter
    autoload :HTTP, "network_resiliency/adapter/http"
    autoload :Faraday, "network_resiliency/adapter/faraday"
    autoload :Redis, "network_resiliency/adapter/redis"
    autoload :Mysql, "network_resiliency/adapter/mysql"
    autoload :Postgres, "network_resiliency/adapter/postgres"
  end

  extend self

  attr_accessor :statsd, :redis

  def configure
    yield self if block_given?

    start_syncing if redis
  end

  def patch(*adapters)
    adapters.each do |adapter|
      case adapter
      when :http
        Adapter::HTTP.patch
      when :redis
        Adapter::Redis.patch
      when :mysql
        Adapter::Mysql.patch
      when :postgres
        Adapter::Postgres.patch
      else
        raise NotImplementedError
      end
    end
  end

  def enabled?(adapter)
    return thread_state["enabled"] if thread_state.key?("enabled")
    return true if @enabled.nil?

    if @enabled.is_a?(Proc)
      # prevent recursive calls
      enabled = @enabled
      disable! { !!enabled.call(adapter) }
    else
      @enabled
    end
  rescue
    false
  end

  def enabled=(enabled)
    unless [ true, false ].include?(enabled) || enabled.is_a?(Proc)
      raise ArgumentError
    end

    @enabled = enabled
  end

  def enable!
    original = @enabled
    thread_state["enabled"] = true

    yield if block_given?
  ensure
    thread_state.delete("enabled") if block_given?
  end

  def disable!
    original = @enabled
    thread_state["enabled"] = false

    yield if block_given?
  ensure
    thread_state.delete("enabled") if block_given?
  end

  def timestamp
    # milliseconds
    Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000
  end

  # private

  IP_ADDRESS_REGEX = Regexp.new(/\d{1,3}(\.\d{1,3}){3}/)

  def record(adapter:, action:, destination:, duration:, error: nil)
    # filter raw IP addresses
    return if IP_ADDRESS_REGEX.match?(destination)

    NetworkResiliency.statsd&.distribution(
      "network_resiliency.#{action}",
      duration,
      tags: {
        adapter: adapter,
        destination: destination,
        error: error,
      }.compact,
    )

    key = [ adapter, action, destination ].join(":")
    StatsEngine.add(key, duration)
  rescue => e
    warn "[ERROR] NetworkResiliency: #{e.class}: #{e.message}"
  end

  def reset
    @enabled = nil
    Thread.current["network_resiliency"] = nil
    StatsEngine.reset
    @sync_worker.kill if @sync_worker
  end

  private

  def thread_state
    Thread.current["network_resiliency"] ||= {}
  end

  def start_syncing
    @sync_worker.kill if @sync_worker

    raise "Redis not configured" unless redis

    @sync_worker = Thread.new do
      while true do
        StatsEngine.sync(redis)

        sleep(3)
      end
    rescue Interrupt
      # goodbye
    end
  end
end
