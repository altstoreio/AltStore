inhibit_all_warnings!

def common_pods
    pod 'Roxas', :git => 'https://github.com/rileytestut/Roxas.git'
end

target 'AltStore' do
  platform :ios, '12.0'

  use_frameworks!

  common_pods

  # Pods for AltStore
  pod 'Nuke', '~> 7.0'
  pod 'AppCenter', '~> 4.2.0'

end

target 'AltServer' do
  platform :macos, '10.14'

  use_frameworks!

  # Pods for AltServer
  pod 'STPrivilegedTask', :git => 'https://github.com/rileytestut/STPrivilegedTask.git'
  pod 'Sparkle'

end

target 'AltStoreCore' do
  platform :ios, '12.0'

  use_frameworks!
  common_pods
  
  # Pods for AltServer
  pod 'KeychainAccess', '~> 4.2.0'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.2'
    end
  end
end