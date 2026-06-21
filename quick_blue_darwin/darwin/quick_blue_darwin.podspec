#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint quick_blue_darwin.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'quick_blue_darwin'
  s.version          = '0.0.1'
  s.summary          = 'Darwin implementation of the quick_blue plugin.'
  s.description      = <<-DESC
Darwin implementation of the quick_blue Bluetooth LE plugin.
                       DESC
  s.homepage         = 'https://github.com/prefanatic/quick_blue'
  s.license          = { :type => 'BSD-3-Clause', :file => '../LICENSE' }
  s.author           = { 'Cody Goldberg' => 'cody@goldberg.fyi' }
  s.source           = { :path => '.' }
  s.source_files     = 'quick_blue_darwin/Sources/quick_blue_darwin/**/*.swift'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
