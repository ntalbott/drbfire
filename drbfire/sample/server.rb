require 'drb/drbfire'

class Front
  include DRbUndumped

  def m(client)
    p "m called"
    client.m
  end
end

host = ARGV[0] || '127.0.0.1'

DRb.start_service("drbfire://#{host}:3333", Front.new, DRbFire::ROLE => DRbFire::SERVER)
DRb.thread.join
