inhibit_all_warnings!

target 'AltStore' do
  platform :ios, '14.0'

  use_frameworks!

  # Pods for AltStore
  pod 'Nuke', :git => 'https://github.com/kean/Nuke.git', :tag => '10.7.1'

end

target 'AltServer' do
  platform :macos, '11'

  use_frameworks!

  # Pods for AltServer
  pod 'STPrivilegedTask', :git => 'https://github.com/rileytestut/STPrivilegedTask.git'
  pod 'Sparkle', :git => 'https://github.com/sparkle-project/Sparkle.git', :tag => '2.3.2'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0'
    end
  end
end