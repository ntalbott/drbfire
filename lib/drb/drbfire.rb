# :include:README
#--
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2004 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'delegate'
require 'drb'
require 'timeout'

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
#
#
# == Caveats
#
# * DRbFire uses a 32-bit id space, meaning ids will wrap after
#   approximately ~4.2 billion connections. If that's a non-theoretical
#   problem for you, and you tell me about it, I'll figure out some
#   way to fix it. It'd be worth it just to find out that DRbFire is
#   being used in such a mind-blowing fashion.
#
# * You're limited to one _server_ per process at this point. You can
#   have (and handle) as many clients as you want (well, ok, so I just
#   said there's really a limit somewhere around 4.2 billion. I'm
#   trying to simplify here). Again, this is possible to deal with,
#   but not something that I've needed at this point and not something
#   I'm guessing is terribly common. Let me know if it's a problem for
#   you.


module DRbFire
  # The current version.
  VERSION = [0, 1, 0]
  
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
  INCOMING_CONN = "1" #:nodoc:
  OUTGOING_CONN = "2" #:nodoc:
  SIGNAL_CONN = "3" #:nodoc:

  class Protocol < SimpleDelegator #nodoc:all
    class ClientServer
      attr_reader :signal_id

      def initialize(uri, config)
        @uri = uri
        @config = config
        @connection = Protocol.open(uri, config, SIGNAL_CONN)
        @signal_id = @connection.read_signal_id
      end

      def uri
        "#{@uri}?#{@signal_id}"
      end

      def accept
        @connection.stream.read(1)
        connection = Protocol.open(@uri, @config, OUTGOING_CONN)
        connection.stream.write([@signal_id].pack(ID_FORMAT))
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
      def open_server(uri, config)
        if(server?(config))
          @client_servers ||= {}
          
          sock = delegate(config).open_server(uri, config)
          
          # get the uri from the delegate, and replace the scheme with drbfire://
          # this allows randomly chosen ports (:0) to work
          scheme = sock.uri.match(/^(.*):\/\//)[1]
          drbfire_uri = sock.uri.sub(scheme, SCHEME)
          
          new(drbfire_uri, sock)
        else
          ClientServer.new(uri, config)
        end
      end

      def open(uri, config, type=INCOMING_CONN)
        unless(server?(config))
          connection = new(uri, delegate(config).open(uri, config))
          connection.stream.write(type)
          connection
        else
          @client_servers[parse_uri(uri).last.to_i].open
        end
      end

      def add_client_connection(id, connection)
        if((c = @client_servers[id]))
          c.push(connection)
        else
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
    end

    attr_reader :signal_id, :uri

    def initialize(uri, delegate)
      super(delegate)
      @uri = uri
      @id = 0
      @id_mutex = Mutex.new
    end

    def accept
      while(__getobj__.instance_eval{@socket})
        begin
          connection = self.class.new(nil, __getobj__.accept)
        rescue IOError
          return nil
        end
        begin
          type = connection.stream.read(1)
        rescue
          next
        end
        case type
        when INCOMING_CONN
          return connection
        when OUTGOING_CONN
          self.class.add_client_connection(connection.read_signal_id, connection)
          next
        when SIGNAL_CONN
          new_id = nil
          @id_mutex.synchronize do
            new_id = (@id += 1)
          end
          client_server = ClientServerProxy.new(connection, new_id)
          self.class.add_client_server(new_id, client_server)
          client_server.write_signal_id
          next
        else
          raise "Invalid type #{type}"
        end
      end
    end

    def read_signal_id
      stream.read(4).unpack(ID_FORMAT).first
    end
  end
end
DRb::DRbProtocol.add_protocol(DRbFire::Protocol)
