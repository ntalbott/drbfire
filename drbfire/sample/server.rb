require 'drb/drbfire'

class Front
  include DRbUndumped

  def m(client)
    p "m called"
    client.m
  end
end

DRb.start_service('drbfire://127.0.0.1:3333', Front.new, DRbFire::ROLE => DRbFire::SERVER)
DRb.thread.join
