# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2004 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'optparse'
require 'drb/drbfire'

class Back
  include DRbUndumped

  def m(param)
    p "m called"
    param.n
  end
end

options = {
  :host => '127.0.0.1',
  :ssl => false,
}

ARGV.options do |o|
  o.on("-o", "--host=HOST", String, "The host to use"){|options[:host]|}
  o.on("-s", "--use-ssl", "Use SSL"){|options[:ssl]|}
  o.on("-h", "--help", "This message"){puts o; exit}
  o.parse!
end

config = {
  DRbFire::ROLE => DRbFire::CLIENT,
}
if(options[:ssl])
  require 'drb/ssl'
  config.update(DRbFire::DELEGATE => DRb::DRbSSLSocket)
end

url = "drbfire://#{options[:host]}:3333"

DRb.start_service(url, nil, config)
s = DRbObject::new(nil, url)
b = Back::new
s.m(b)
