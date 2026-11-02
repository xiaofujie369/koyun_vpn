# 在 CI（macOS）上给 Runner.xcodeproj 加入 PacketTunnel 网络扩展 target。
# 用法：gem install xcodeproj && ruby ios/add_packet_tunnel.rb
# 只需执行一次；重复执行会跳过。
require 'xcodeproj'

proj_path = File.join(__dir__, 'Runner.xcodeproj')
proj = Xcodeproj::Project.open(proj_path)
exit 0 if proj.targets.any? { |t| t.name == 'PacketTunnel' }

app = proj.targets.find { |t| t.name == 'Runner' }
team = ENV['APPLE_TEAM_ID'].to_s

ext = proj.new_target(:app_extension, 'PacketTunnel', :ios, '15.0')
group = proj.main_group.find_subpath('PacketTunnel', true)
group.set_source_tree('<group>')
group.set_path('PacketTunnel')
shared = proj.main_group.find_subpath('Shared', true)
shared.set_source_tree('<group>')
shared.set_path('Shared')

ext_src = group.new_file('PacketTunnelProvider.swift')
shared_src = shared.new_file('KoyunShared.swift')
group.new_file('Info.plist')
group.new_file('PacketTunnel.entitlements')
ext.add_file_references([ext_src, shared_src])
app.add_file_references([shared_src])

# Libbox.xcframework（CI 里用 gomobile 编译到 ios/Frameworks/）
fw_group = proj.main_group.find_subpath('Frameworks', true)
libbox = fw_group.new_file('Frameworks/Libbox.xcframework')
ext.frameworks_build_phase.add_file_reference(libbox)
ne = proj.frameworks_group.new_file('System/Library/Frameworks/NetworkExtension.framework', :sdk_root)
ext.frameworks_build_phase.add_file_reference(ne)
app.frameworks_build_phase.add_file_reference(ne)

ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.koyun.vpn.PacketTunnel'
  s['PRODUCT_NAME'] = 'PacketTunnel'
  s['INFOPLIST_FILE'] = 'PacketTunnel/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'PacketTunnel/PacketTunnel.entitlements'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['FRAMEWORK_SEARCH_PATHS'] = ['$(inherited)', '$(PROJECT_DIR)/Frameworks']
  s['OTHER_LDFLAGS'] = ['$(inherited)', '-lresolv']
  s['ENABLE_BITCODE'] = 'NO'
  s['SKIP_INSTALL'] = 'YES'
  s['DEVELOPMENT_TEAM'] = team unless team.empty?
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['FLUTTER_BUILD_NAME'] = '$(FLUTTER_BUILD_NAME)'
end

app.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  c.build_settings['DEVELOPMENT_TEAM'] = team unless team.empty?
end

# 把扩展嵌入主 App
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
app.add_dependency(ext)

# 扩展必须在 Flutter "Thin Binary" 脚本之前编译完成
thin = app.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  app.build_phases.delete(embed)
  app.build_phases.insert(app.build_phases.index(thin), embed)
end

proj.save
puts 'PacketTunnel target added'
