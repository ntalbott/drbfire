require 'drb/drbfire'

class Back
  include DRbUndumped

  def m
    p "m called"
  end
end

DRb.start_service('drbfire://127.0.0.1:3333', nil, DRbFire::ROLE => DRbFire::CLIENT)
s = DRbObject::new(nil, 'drbfire://127.0.0.1:3333')
b = Back::new
s.m(b)
