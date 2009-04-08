# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{drbfire}
  s.version = "0.1.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Nathaniel Talbott"]
  s.date = %q{2009-02-07}
#   s.default_executable = %q{deep_test}
  s.description = %q{DRbFire allows easy bidirectional DRb communication in the presence of a firewall.}
  s.email = %q{drbfire@talbott.ws}
#   s.executables = ["deep_test"]
  s.extra_rdoc_files = ["README", "ChangeLog"]
  s.files = ["ChangeLog", "drbfire.gemspec", "INSTALL", "lib/drb/drbfire.rb", "README", "sample/client.rb", "sample/server.rb", "setup.rb", "test/test_drbfire.rb"]
  s.has_rdoc = true
  s.homepage = %q{http://rubyforge.org/projects/drbfire}
  s.rdoc_options = ["--title", "DRbFire", "--main", "README", "--line-numbers"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{drbfire}
  s.rubygems_version = %q{1.3.0}
  s.summary = %q{DRbFire allows easy bidirectional DRb communication in the presence of a firewall.}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
