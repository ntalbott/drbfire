require 'drb'

if(false)
  Thread.abort_on_exception = true
  
  require 'pp'

  class TCPSocket
    alias _recvfrom recvfrom
    def recvfrom(amount)
      pp [addr, "receiving from", amount]
      value = _recvfrom(amount)
      pp [addr, 'received from', value]
      value
    end
    
    alias _recv recv
    def recv(amount)
      pp [addr, 'receiving', amount]
      value = _recv(amount)
      pp [addr, 'received', value]
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
  ROLE = "#{self}::ROLE"
  SERVER = "#{self}::SERVER"
  CLIENT = "#{self}::CLIENT"
  SCHEME = "drbfire"

  class Protocol < DRb::DRbTCPSocket
    class ClientServer
      attr_reader :signal_id

      def initialize(uri, config)
        @uri = uri
        @config = config
        @connection = Protocol.open(Protocol.signal_uri(uri), config, nil)
        @connection.is_signal = true
        @signal_id = @connection.recv_signal_id
      end

      def uri
        "#{@uri}?#{@signal_id}"
      end

      def accept
        @connection.stream.recv(1)
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

      def open_server(uri, config, signal=false)
        if(server?(config))
          signal_server = open_signal_server(uri, config) unless(signal)
          server = super(uri, config)
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
          connection = super(uri, config)
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

    def initialize(uri, socket, config={})
      super
      @signal_socket = nil
      @signal_server_thread = nil
      @is_signal = false
    end

    def close
      if(@signal_server_thread)
        @signal_server_thread.kill
      end
      super
      if(@signal_socket)
        @signal_socket.close
        @signal_socket = nil
      end
    end

    def accept
      if(@is_signal)
        connection = super
        connection.is_signal = true
        connection
      else
        while(@socket)
          begin
            connection = super
          rescue IOError
            return nil
          end
          id = connection.stream.recv(4).unpack("L").first
          return connection if(id == 0)
          Protocol.client_servers[id].push(connection)
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

    def recv_signal_id
      stream.recv(4).unpack("L").first
    end
  end
end
DRb::DRbProtocol.add_protocol(DRbFire::Protocol)
