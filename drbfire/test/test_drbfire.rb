require 'test/unit'
require 'socket'
require 'timeout'
require 'pp'
require 'ostruct'
require 'drb/drb'
require 'drb/ssl'

require 'drb/drbfire'

Thread.abort_on_exception = true

module DRbFire
  class TC_Protocol < Test::Unit::TestCase
    TEST_IP = "127.0.0.1"
    TEST_PORT = 44324
    TEST_SIGNAL_PORT = TEST_PORT + 1
    TEST_URI = ["drbfire://", [TEST_IP, TEST_PORT].join(":")].join('')
    TEST_SERVER_CONFIG = {ROLE => SERVER}
    TEST_CLIENT_CONFIG = {ROLE => CLIENT}

    class TC_ClientServer < Test::Unit::TestCase
      def test_accept
        main = TCPServer.new(TEST_IP, TEST_PORT)
        signal = TCPServer.new(TEST_IP, TEST_SIGNAL_PORT)
        Thread.start do
          client = signal.accept
          client.write([5].pack("L"))
          client.write(0)
          client = main.accept
          client.write("a")
        end
        s = Protocol::ClientServer.new(TEST_URI, TEST_CLIENT_CONFIG)
        c = s.accept
        assert_equal("a", c.stream.read(1))
      ensure
        main.close if(main)
        signal.close if(signal)
      end
    end
    
    def test_SERVER_open_server
      s = Protocol.open_server(TEST_URI, TEST_SERVER_CONFIG)
      assert_nothing_raised do
        main = TCPSocket.open(TEST_IP, TEST_PORT)
        signal = TCPSocket.open(TEST_IP, TEST_SIGNAL_PORT)
        signal2 = TCPSocket.open(TEST_IP, TEST_SIGNAL_PORT)
        begin
          timeout(1) do
            c = TCPSocket.open(TEST_IP, TEST_PORT)
            id = signal.read(4).unpack("L").first
            c.write([id].pack("L"))
            assert_equal(1, id)
            assert_equal(2, signal2.read(4).unpack("L").first)
          end
        ensure
          s.close
        end
      end
      assert_nothing_raised do
        TCPServer.new(TEST_IP, TEST_PORT).close
        TCPServer.new(TEST_IP, TEST_SIGNAL_PORT).close
      end
    end

    def test_SERVER_open
      s = Protocol.open_server(TEST_URI, TEST_SERVER_CONFIG)
      Thread.start do
        2.times do
          s.accept
        end
      end
      main = TCPSocket.open(TEST_IP, TEST_PORT)
      main.write([0].pack("L"))
      signal = TCPSocket.open(TEST_IP, TEST_SIGNAL_PORT)
      id = signal.read(4).unpack("L").first
      requested = received = false
      m = Mutex.new
      Thread.start do
        signal.read(1)
        requested = true
        new_conn = TCPSocket.open(TEST_IP, TEST_PORT)
        m.synchronize do
          new_conn.write([id].pack("L"))
          received = new_conn.read(1) rescue nil
        end
      end
      c = nil
      assert_nothing_raised do
        timeout(1) do
          c = Protocol.open("#{TEST_URI}?#{id}", TEST_SERVER_CONFIG)
        end
      end
      c.stream.write("a")
      assert(requested)
      m.synchronize do
        assert_equal("a", received)
      end
    ensure
      c.close if(c)
      s.close if(s)
    end

    def test_CLIENT_open_server
      m = Mutex.new
      cv = ConditionVariable.new
      accepted = false
      s = c = nil
      s = TCPServer.new(TEST_IP, TEST_SIGNAL_PORT)
      t = Thread.start do
        begin
          timeout(2) do
            c = s.accept
            c.write([5].pack("L"))
            c = s.accept
            c.write([7].pack("L"))
          end
        rescue TimeoutError
          accepted = false
        else
          accepted = true
        end
        m.synchronize do
          c.close
          s.close
          cv.signal
        end
      end
      
      server = nil
      m.synchronize do
        begin
          server = Protocol.open_server(TEST_URI, TEST_CLIENT_CONFIG)
          assert_equal(5, server.signal_id)
          server = Protocol.open_server(TEST_URI, TEST_CLIENT_CONFIG)
          assert_equal(7, server.signal_id)
        ensure
          server.close if(server)
        end
      end
      sleep(0.1)
      cv.wait(m)
      assert(accepted)
    end

    def test_CLIENT_open
      m = Mutex.new
      cv = ConditionVariable.new
      accepted = false
      id = nil
      
      s = c = nil
      s = TCPServer.new(TEST_IP, TEST_PORT)
      t = Thread.start do
        begin
          timeout(1) do
            c = s.accept
            id = c.read(4).unpack("L").first
          end
        rescue TimeoutError
          accepted = false
        else
          accepted = true
        end
        m.synchronize do
          s.close
          cv.signal
        end
      end
      
      m.synchronize do
        assert_nothing_raised do
          begin
            p = Protocol.open(TEST_URI, TEST_CLIENT_CONFIG)
          ensure
            p.close if(p)
          end
        end
        cv.wait(m)
        assert(accepted)
        assert_equal(0, id)
      end
    end

    def test_parse_uri
      assert_raise(DRb::DRbBadScheme) do
        Protocol.parse_uri("druby://localhost:0")
      end
      assert_raise(DRb::DRbBadURI) do
        Protocol.parse_uri("drbfire://localhost")
      end
      assert_equal(['localhost', 0, 'option&stuff'], Protocol.parse_uri("drbfire://localhost:0?option&stuff"))
    end

    def test_uri_option
      assert_equal(['drbfire://localhost:0', 'option&stuff'], Protocol.uri_option("drbfire://localhost:0?option&stuff", {}))
    end

    class Front
      include DRbUndumped

      class Param
	include DRbUndumped

	attr_reader :called

	def initialize
	  @called = false
	end

	def n
	  @called = true
	end
      end

      attr_reader :called, :param

      def initialize
        @called = 0
	@param = Param.new
      end

      def param_called
	@param.called
      end
      
      def m(args={})
        @called += 1
        args[:back].m(:param => @param) if(args[:back])
	args[:param].n if(args[:param])
      end
    end

    def check_communication
      config = OpenStruct.new(
        :start_server => true,
        :stop_server => true,
        :server => nil,
        :front => Front.new,
        :server_config => TEST_SERVER_CONFIG,
        :client_config => TEST_CLIENT_CONFIG)
      yield(config) if(block_given?)
      begin
        config.server = DRb.start_service(TEST_URI, config.front, config.server_config) if(config.start_server)
        client = nil
        assert_nothing_raised do
          timeout(1) do
            client = DRb.start_service(TEST_URI, nil, config.client_config)
          end
        end
        client_front = DRbObject.new(nil, TEST_URI)
        back = Front.new
        assert_nothing_raised do
          timeout(1) do
            client_front.m(:back => back)
          end
        end
        assert(0 < config.front.called, "Server not called")
	assert(config.front.param_called, "Server not called back")
        assert_equal(1, back.called, "Client not called")
      ensure
        client.stop_service if(client)
        config.server.stop_service if(config.server && config.stop_server)
      end
      assert_nothing_raised do
        TCPServer.new(TEST_IP, TEST_PORT).close
      end if(config.stop_server)
      return config.server, config.front
    end
    
    def test_normal_communication
      check_communication
    end

    def test_connect_twice
      server, front = check_communication do |config|
        config.start_server = true
        config.stop_server = false
      end
      check_communication do |config|
        config.start_server = false
        config.stop_server = true
        config.server = server
        config.front = front
      end
    end

    def test_ssl_communication
      check_communication do |config|
        config.server_config = TEST_SERVER_CONFIG.dup.update(DELEGATE => DRb::DRbSSLSocket,
          :SSLCertName => [ ["C","US"], ["O","localhost"], ["CN", "Temporary"] ])
        config.client_config = TEST_CLIENT_CONFIG.dup.update(DELEGATE => DRb::DRbSSLSocket)
      end
    end
  end
end
