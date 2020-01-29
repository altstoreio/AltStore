inhibit_all_warnings!

target 'AltStore' do
  platform :ios, '12.0'

  use_modular_headers!

  # Pods for AltStore
  pod 'KeychainAccess', '~> 3.2.0'
  pod 'Nuke', '~> 7.0'
  pod 'AltSign', :path => 'Dependencies/AltSign'
  pod 'Roxas', :path => 'Dependencies/Roxas'

end

target 'AltServer' do
  platform :macos, '10.14'

  use_frameworks!

  # Pods for AltServer
  pod 'STPrivilegedTask'
  pod 'Sparkle'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.2'
    end
  end
end