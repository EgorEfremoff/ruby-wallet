module RubyWallet
  module Version
    MAJOR = 0
    MINOR = 4
    PATCH = 3
    STRING =[MAJOR, MINOR, PATCH].join('.')
  end
  VERSION = Version::STRING
end
