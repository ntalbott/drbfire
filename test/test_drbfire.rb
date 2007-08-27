# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2004 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

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
    TEST_URI = ["drbfire://", [TEST_IP, TEST_PORT].join(":")].join('')
    TEST_SERVER_CONFIG = {ROLE => SERVER}
    TEST_CLIENT_CONFIG = {ROLE => CLIENT}

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
        DRb.remove_server config.server # Hack to deal with running multiple servers in the same process - we always want the client server to be picked up.
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
