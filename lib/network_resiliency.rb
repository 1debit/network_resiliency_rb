require "network_resiliency/version"

module NetworkResiliency
  module Adapter
    autoload :HTTP, "network_resiliency/adapter/http"
    autoload :Faraday, "network_resiliency/adapter/faraday"
    autoload :Redis, "network_resiliency/adapter/redis"
  end

  extend self

  attr_accessor :statsd

  def configure
    yield self
  end

  def patch(*adapters)
    adapters.each do |adapter|
      case adapter
      when :http
        Adapter::HTTP.patch
      when :redis
        Adapter::Redis.patch
      else
        raise NotImplementedError
      end
    end
  end

  def enabled?(adapter)
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
    @enabled = true

    yield if block_given?
  ensure
    @enabled = original if block_given?
  end

  def disable!
    original = @enabled
    @enabled = false

    yield if block_given?
  ensure
    @enabled = original if block_given?
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
  end

  def reset
    @enabled = nil
  end
end
