require 'optparse'
require 'drb/drbfire'

class Front
  include DRbUndumped

  def m(client)
    p "m called"
    client.m(Param.new)
  end
end

class Param
  include DRbUndumped

  def n
    p "n called"
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
  DRbFire::ROLE => DRbFire::SERVER,
}
if(options[:ssl])
  require 'drb/ssl'
  config.update(DRbFire::DELEGATE => DRb::DRbSSLSocket,
    :SSLCertName => [ ["C","US"], ["O",options[:host]], ["CN", "Temporary"] ])
end
DRb.start_service("drbfire://#{options[:host]}:3333", Front.new, config)
DRb.thread.join
