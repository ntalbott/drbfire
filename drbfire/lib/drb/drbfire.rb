require 'delegate'
require 'drb'

if(false)
  Thread.abort_on_exception = true
  
  require 'pp'

  class TCPSocket
    alias _read read
    def read(amount)
      pp [addr, 'reading', amount]
      value = _read(amount)
      pp [addr, 'read', value]
      value
    end

    alias _write write
    def write(value)
      pp [addr, 'writing', value]
      _write(value)
    end
  end

  class TCPServer
    alias _accept accept
    def accept
      pp ['accepting', addr]
      client = _accept
      pp ['accepted', client.peeraddr]
      client
    end
  end
end

module DRbFire
  # Configuration keys
  ROLE = "#{self}::ROLE"
  DELEGATE = "#{self}::DELEGATE"

  # Configuration values
  SERVER = "#{self}::SERVER"
  CLIENT = "#{self}::CLIENT"

  # Miscellaneous constants
  SCHEME = "drbfire"

  class Protocol < SimpleDelegator
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
        @connection.stream.write([id].pack("L"))
        @queue = Queue.new
      end

      def push(connection)
        @queue.push(connection)
      end

      def open
        @connection.stream.write("0")
        @queue.pop
      end
    end

    class << self
      attr_reader :client_servers

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
            end
          end
          @delegate.delegate = self
        end
        @delegate
      end

      def open_server(uri, config, signal=false)
        if(server?(config))
          signal_server = open_signal_server(uri, config) unless(signal)
          server = new(delegate(config).open_server(uri, config))
          server.signal_socket = signal_server
          server
        else
          ClientServer.new(uri, config)
        end
      end

      def open_signal_server(uri, config)
        @client_servers ||= {}
        signal_server = open_server(signal_uri(uri), config, true)
        signal_server.is_signal = true
        signal_server.start_signal_server
        signal_server
      end

      def open(uri, config, id=0)
        unless(server?(config))
          connection = new(delegate(config).open(uri, config))
          connection.stream.write([id].pack("L")) if(id)
          connection
        else
          @client_servers[parse_uri(uri).last.to_i].open
        end
      end

      def signal_uri(uri)
        parts = parse_uri(uri)
        parts[1] += 1
        signal_uri = "#{SCHEME}://%s:%d?%s" % parts
        signal_uri.sub(/\?$/, '')
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
    end

    attr_writer :signal_socket
    attr_reader :signal_id
    attr_writer :is_signal

    def initialize(delegate)
      super
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
        connection = self.class.new(__getobj__.accept)
        connection.is_signal = true
        connection
      else
        while(__getobj__.instance_eval{@socket})
          begin
            connection = self.class.new(__getobj__.accept)
          rescue IOError
            return nil
          end
          id = connection.stream.read(4).unpack("L").first
          return connection if(id == 0)
          self.class.client_servers[id].push(connection)
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
            m.synchronize do
              self.class.client_servers[new_id] = client_server
            end
          end
        end
      end
    end

    def read_signal_id
      stream.read(4).unpack("L").first
    end
  end
end
DRb::DRbProtocol.add_protocol(DRbFire::Protocol)
