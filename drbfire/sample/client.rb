require 'drb/drbfire'

class Back
  include DRbUndumped

  def m
    p "m called"
  end
end

host = ARGV[0] || '127.0.0.2'
url = "drbfire://#{host}:3333"

DRb.start_service(url, nil, DRbFire::ROLE => DRbFire::CLIENT)
s = DRbObject::new(nil, url)
b = Back::new
s.m(b)
