gem "mysql2", ">= 0.5"
require "mysql2"

module NetworkResiliency
  module Adapter
    module Mysql
      extend self

      def patch
        return if patched?

        Mysql2::Client.prepend(Instrumentation)
      end

      def patched?
        Mysql2::Client.ancestors.include?(Instrumentation)
      end

      module Instrumentation
        def connect(_, _, host, *args)
          # timeout = query_options[:connect_timeout]

          return super unless NetworkResiliency.enabled?(:mysql)

          begin
            ts = -NetworkResiliency.timestamp

            super
          rescue Mysql2::Error::TimeoutError => e
            # capture error
            raise
          ensure
            ts += NetworkResiliency.timestamp

            NetworkResiliency.record(
              adapter: "mysql",
              action: "connect",
              destination: host,
              error: e&.class,
              duration: ts,
            )
          end
        end

        # def query(sql, options = {})
        #   puts "query"
        #   super
        # end
      end
    end
  end
end