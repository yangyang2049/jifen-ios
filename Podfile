source 'https://cdn.cocoapods.org/'

platform :ios, '18.0'

target 'jifen' do
  pod 'UMCommon'

  target 'jifenTests' do
    inherit! :search_paths
  end

  target 'jifenUITests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
    end
  end
end
