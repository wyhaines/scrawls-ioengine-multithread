require 'scrawls/ioengine/multithread/version'
require 'scrawls/ioengine/multiprocess'
require 'socket'
require 'mime-types'
require 'scrawls/config/task'
require 'scrawls/config/tasklist'
require 'thread/pool'

module Scrawls
  module Ioengine
    class Multithread < Scrawls::Ioengine::Multiprocess

      def initialize(scrawls)
        @scrawls = scrawls
        @thread_pool = nil
      end

      def run( config = {} )
        server = TCPServer.new( config[:host], config[:port] )

        fork_it( config[:processes] - 1 )

        create_thread_pool( config[:thread_pool] )

        do_main_loop server
      end

      def create_thread_pool( pool_size = nil )
        @thread_pool = Thread::Pool.new( *pool_size ) if pool_size
      end

      def do_main_loop server
        while con = server.accept
          if @thread_pool
            @thread_pool.process( con ) do |connection|
              _do_main_loop( connection )
            end
          else
            Thread.new( con ) do |connection|
              _do_main_loop( connection )
            end
          end
        end
      end

      def _do_main_loop connection
        Thread.current[:connection] = connection
        request = get_request connection
        cork_tcp_socket connection
        response = handle request
        uncork_tcp_socket connection

        close
      end

      def self.parse_command_line(configuration, meta_configuration)
        call_list = SimpleRubyWebServer::Config::TaskList.new

        configuration[:thread_pool] = nil
        configuration[:processes] = 1

        meta_configuration[:helptext] << <<-EHELP
--processes COUNT:
  The number of processes to fork. Defaults to 1.

-s SIZE|MINSIZE,MAXSIZE, --pool-size SIZE|MINSIZE,MAXSIZE:
  The size of the thread pool to create. If unset, Scrawls will spawn a thread for each request. If given two comman separated numbers, those numbers will be interpreted to be the minimum and maximum size of the thread pool. Scrawls will spawn new threads as needed, to the maximum number, if all threads are busy, and will later reduce the size of the thread pool back down toward the minimum size if the threads become idle.

EHELP

        options = OptionParser.new do |opts|
          opts.on( '--processes COUNT' ) do |count|
            call_list << SimpleRubyWebServer::Config::Task.new(9000) { n = Integer( count.to_i ); n = n > 0 ? n : 1; configuration[:processes] = n }
          end

          opts.on( '--s', '--pool-size SIZE' ) do |size|
            call_list << SimpleRubyWebServer::Config::Task.new(9000) do
              n = nil

              if size =~ /\s*(\d+)\s*,\s*(\d+)/
                n = [ $1.to_i, $2.to_i > 0 ? $2.to_i : 1 ]
              else
                n = Integer( size.to_i )
                n = n > 0 ? [ n ] : nil
              end

              configuration[:thread_pool] = n
            end
          end
        end

        leftover_argv = []

        begin
          options.parse!(ARGV)
        rescue OptionParser::InvalidOption => e
          e.recover ARGV
          leftover_argv << ARGV.shift
          leftover_argv << ARGV.shift if ARGV.any? && ( ARGV.first[0..0] != '-' )
          retry
        end

        ARGV.replace( leftover_argv ) if leftover_argv.any?

        call_list
      end

    end
  end
end
