require 'scrawls/ioengine/multithread/version'
require 'scrawls/ioengine/multiprocess'
require 'socket'
require 'mime-types'
require 'scrawls/config/task'
require 'scrawls/config/tasklist'

module Scrawls
  module Ioengine
    class Multithread < Scrawls::Ioengine::Multiprocess

      def initialize(scrawls)
        @scrawls = scrawls
      end

      def do_main_loop server
        while con = server.accept
          Thread.new( con ) do |connection|
            Thread.current[:connection] = connection
            request = get_request connection
            response = handle request

            close
          end
        end
      end

    end
  end
end
