require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "rntwilio"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.description  = <<-DESC
                  RNTwilio
                   DESC
  s.homepage     = "https://github.com/liyamahendra"
  s.license      = "MIT"
  # s.license    = { :type => "MIT", :file => "FILE_LICENSE" }
  s.authors      = { "Mahendra Liya" => "liyamahendra4@gmail.com" }
  s.platform     = :ios, "10.0"
  s.source       = { :git => "https://github.com/liyamahendra/rn-twilio", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,swift}"
  s.requires_arc = true

  s.dependency "React"
  s.dependency 'TwilioVoice', '~> 5.5.2'
end

