# :include:README
#--
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2004 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'delegate'
require 'drb'

# = DRb Firewall Protocol
# 
# == Prerequisites
#
# It is assumed that you already know how to use DRb; if you don't
# you'll need to go read up on it and understand the basics of how it
# works before using DRbFire. DRbFire actually wraps the standard
# protocols that DRb uses, so generally anything that applies to them
# applies to DRbFire.
#
#
# == Basic Usage
# 
# Using DRbFire is quite simple, and can be summed up in four steps:
#
# 1. Start with <tt>require 'drb/drbfire'</tt>.
#
# 2. Use <tt>drbfire://</tt> instead of <tt>druby://</tt> when
#    specifying the server url.
#
# 3. When calling <tt>DRb.start_service</tt> on the client, specify
#    the server's uri as the uri (as opposed to the normal usage, which
#    is to specify *no* uri).
#
# 4. Specify the right configuration when calling
#    <tt>DRb.start_service</tt>, specifically the role to use:
#    On the server:: <tt>DRbFire::ROLE => DRbFire::SERVER</tt>
#    On the client:: <tt>DRbFire::ROLE => DRbFire::CLIENT</tt>
#
# So a simple server would look like:
#
#   require 'drb/drbfire'
#
#   front = ['a', 'b', 'c']
#   DRb.start_service('drbfire://some.server.com:5555', front, DRbFire::ROLE => DRbFire::SERVER)
#   DRb.thread.join
#
# And a simple client:
#
#   require 'drb/drbfire'
#
#   DRb.start_service('drbfire://some.server.com:5555', nil, DRbFire::ROLE => DRbFire::CLIENT)
#   DRbObject.new(nil, 'drbfire://some.server.com:5555').each do |e|
#     p e
#   end
#
# 
# == Advanced Usage
#
# You can do some more interesting tricks with DRbFire, too:
#
# <b>Using SSL</b>:: To do this, you have to set the delegate in the
#                    configuration (on both the server and the client) using
#                    <tt>DRbFire::DELEGATE => DRb::DRbSSLSocket</tt>. Other
#                    DRb protcols may also work as delegates, but only the
#                    SSL protocol is tested.


module DRbFire
  # The current version.
  VERSION = [0, 0, 6]
  
  # The role configuration key.
  ROLE = "#{self}::ROLE"

  # The server role configuration value.
  SERVER = "#{self}::SERVER"

  # The client role configuration value.
  CLIENT = "#{self}::CLIENT"

  # The delegate configuration key.
  DELEGATE = "#{self}::DELEGATE"

  # Miscellaneous constants
  SCHEME = "drbfire" #:nodoc:
  ID_FORMAT = "N" #:nodoc:
  DEBUG = proc{|*a| p a if($DEBUG)} #:nodoc:

  class Protocol < SimpleDelegator #nodoc:all
    class ClientServer
      attr_reader :signal_id

      def initialize(uri, config)
        @uri = uri
        @config = config
        @connection = Protocol.open(Protocol.signal_uri(uri), config, nil)
        @connection.is_signal = true
        @signal_id = @connection.read_signal_id
      end

      def uri
        "#{@uri}?#{@signal_id}"
      end

      def accept
        @connection.stream.read(1)
        connection = Protocol.open(@uri, @config, @signal_id)
        connection
      end

      def close
        @connection.close
      end
    end

    class ClientServerProxy
      def initialize(connection, id)
        @connection = connection
        @id = id
        @queue = Queue.new
      end

      def write_signal_id
	DEBUG["writing id", @id]
        @connection.stream.write([@id].pack(ID_FORMAT))
      end

      def push(connection)
        @queue.push(connection)
      end

      def open
        @connection.stream.write("0")
        timeout(20) do
          @queue.pop
        end
      rescue TimeoutError
        raise DRb::DRbConnError, "Unable to get a client connection."
      end
    end

    class << self
      def open_server(uri, config, signal=false)
	DEBUG['open_server', uri, config, signal]
        if(server?(config))
          signal_server = open_signal_server(uri, config) unless(signal)
          server = new(uri, delegate(config).open_server(uri, config))
          server.signal_socket = signal_server
          server
        else
          ClientServer.new(uri, config)
        end
      end

     def open(uri, config, id=0)
	DEBUG['open', uri, config, id]
        unless(server?(config))
          connection = new(uri, delegate(config).open(uri, config))
	  DEBUG["writing id", id] if(id)
          connection.stream.write([id].pack(ID_FORMAT)) if(id)
          connection
        else
          @client_servers[parse_uri(uri).last.to_i].open
        end
      end

      def add_client_connection(id, connection)
        if((c = @client_servers[id]))
          c.push(connection)
        else
          DEBUG['add_client_connection', 'invalid client', id]
        end
      end

      def add_client_server(id, server)
        @client_servers[id] = server
      end

     def parse_uri(uri)
        if(%r{^#{SCHEME}://([^:]+):(\d+)(?:\?(.+))?$} =~ uri)
          [$1, $2.to_i, $3]
        else
          raise DRb::DRbBadScheme, uri unless(/^#{SCHEME}/ =~ uri)
          raise DRb::DRbBadURI, "Can't parse uri: #{uri}"
        end
      end

      def uri_option(uri, config)
        host, port, option = parse_uri(uri)
        return "#{SCHEME}://#{host}:#{port}", option
      end

      def signal_uri(uri)
        parts = parse_uri(uri)
        parts[1] += 1
        signal_uri = "#{SCHEME}://%s:%d?%s" % parts
        signal_uri.sub(/\?$/, '')
      end

      private

      def server?(config)
        raise "Invalid configuration" unless(config.include?(ROLE))
        config[ROLE] == SERVER
      end

      def delegate(config)
        unless(defined?(@delegate))
          @delegate = Class.new(config[DELEGATE] || DRb::DRbTCPSocket) do
            class << self
              attr_writer :delegate

              def parse_uri(uri)
                @delegate.parse_uri(uri)
              end

	      def uri_option(uri, config)
		@delegate.uri_option(uri, config)
	      end
            end
          end
          @delegate.delegate = self
        end
        @delegate
      end

      def open_signal_server(uri, config)
        @client_servers ||= {}
        signal_server = open_server(signal_uri(uri), config, true)
        signal_server.is_signal = true
        signal_server.start_signal_server
        signal_server
      end
    end

    attr_writer :signal_socket, :is_signal
    attr_reader :signal_id, :uri

    def initialize(uri, delegate)
      super(delegate)
      @uri = uri
      @signal_socket = nil
      @signal_server_thread = nil
      @is_signal = false
    end

    def close
      if(@signal_server_thread)
        @signal_server_thread.kill
      end
      __getobj__.close
      if(@signal_socket)
        @signal_socket.close
        @signal_socket = nil
      end
    end

    def accept
      if(@is_signal)
        connection = self.class.new(nil, __getobj__.accept)
        connection.is_signal = true
        connection
      else
        while(__getobj__.instance_eval{@socket})
          begin
            connection = self.class.new(nil, __getobj__.accept)
          rescue IOError
            return nil
          end
          begin
            id = connection.stream.read(4).unpack(ID_FORMAT).first
          rescue
            next
          end
          next unless(id)
	  DEBUG["accepted id", id]
          return connection if(id == 0)
          self.class.add_client_connection(id, connection)
        end
      end
    end

    def start_signal_server
      @signal_server_thread = Thread.start(self) do |server|
        id = 0
        m = Mutex.new
        loop do
          Thread.start(server.accept) do |client|
            new_id = nil
            m.synchronize do
              new_id = (id += 1)
            end
            client_server = ClientServerProxy.new(client, new_id)
            self.class.add_client_server(new_id, client_server)
            client_server.write_signal_id
          end
        end
      end
    end

    def read_signal_id
      id = stream.read(4).unpack(ID_FORMAT).first
      DEBUG["read_signal_id", id]
      id
    end
  end
end
DRb::DRbProtocol.add_protocol(DRbFire::Protocol)
