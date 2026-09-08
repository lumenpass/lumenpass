#!/usr/bin/env ruby
# frozen_string_literal: true
# ---------------------------------------------------------------------------
# Wires the LumenPass AutoFill credential provider extension into the Xcode
# project. Run once from `apps/mobile/ios`:
#
#     ruby setup_autofill_target.rb
#
# The script is idempotent – you can re-run it safely. It only adds what's
# missing.
# ---------------------------------------------------------------------------

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH        = File.expand_path('Runner.xcodeproj', __dir__)
RUNNER_NAME         = 'Runner'
EXTENSION_NAME      = 'LumenPassAutoFill'
EXTENSION_DIR       = File.expand_path(EXTENSION_NAME, __dir__)
SHARED_DIR          = File.expand_path('Shared', __dir__)
BUNDLE_PREFIX       = 'com.tranit.lumenpass.ios'
EXTENSION_BUNDLE_ID = "#{BUNDLE_PREFIX}.autofill"

project = Xcodeproj::Project.open(PROJECT_PATH)

# ---------------------------------------------------------------------------
# 1. Shared source group – `LumenPassSharedStore.swift` is linked into both
#    the main app and the extension.
# ---------------------------------------------------------------------------
shared_group = project.main_group['Shared'] ||
               project.main_group.new_group('Shared', 'Shared')

shared_store_ref  = shared_group.files.find { |f| f.path == 'LumenPassSharedStore.swift' } ||
                    shared_group.new_file('LumenPassSharedStore.swift')

# ---------------------------------------------------------------------------
# 2. Make sure Runner app links the shared helper + bridge file.
# ---------------------------------------------------------------------------
runner_target = project.targets.find { |t| t.name == RUNNER_NAME }
raise "Could not find Runner target" unless runner_target

runner_group = project.main_group[RUNNER_NAME] || project.main_group.new_group(RUNNER_NAME, RUNNER_NAME)

bridge_rel_path = 'AutoFillBridgePlugin.swift'
bridge_ref      = runner_group.files.find { |f| f.path == bridge_rel_path } ||
                  runner_group.new_file(bridge_rel_path)

runner_sources_phase = runner_target.source_build_phase
unless runner_sources_phase.files_references.include?(bridge_ref)
  runner_sources_phase.add_file_reference(bridge_ref)
end
unless runner_sources_phase.files_references.include?(shared_store_ref)
  runner_sources_phase.add_file_reference(shared_store_ref)
end

# Add App Group + AuthenticationServices to Runner
runner_target.frameworks_build_phase.tap do |phase|
  existing = phase.files_references.map(&:path)
  unless existing.include?('System/Library/Frameworks/AuthenticationServices.framework')
    ref = project.frameworks_group.new_reference(
      'System/Library/Frameworks/AuthenticationServices.framework'
    )
    ref.source_tree = 'SDKROOT'
    phase.add_file_reference(ref)
  end
end

# ---------------------------------------------------------------------------
# 3. Create the AutoFill extension target if it doesn't exist yet.
# ---------------------------------------------------------------------------
extension_target = project.targets.find { |t| t.name == EXTENSION_NAME }

unless extension_target
  extension_target = project.new_target(
    :app_extension,
    EXTENSION_NAME,
    :ios,
    '14.0'
  )
end

extension_target.product_type = 'com.apple.product-type.app-extension'

# Extension group in the project navigator
extension_group = project.main_group[EXTENSION_NAME] ||
                  project.main_group.new_group(EXTENSION_NAME, EXTENSION_NAME)

extension_sources = %w[
  CredentialProviderViewController.swift
  CredentialListViewController.swift
]
info_plist_path = 'Info.plist'
entitlements_path = "#{EXTENSION_NAME}.entitlements"

# Source files
extension_sources.each do |name|
  ref = extension_group.files.find { |f| f.path == name } ||
        extension_group.new_file(name)
  unless extension_target.source_build_phase.files_references.include?(ref)
    extension_target.source_build_phase.add_file_reference(ref)
  end
end

# Plist + entitlements: add to group but don't put them in build phases.
[info_plist_path, entitlements_path].each do |name|
  unless extension_group.files.any? { |f| f.path == name }
    extension_group.new_file(name)
  end
end

# Link shared helper into extension
unless extension_target.source_build_phase.files_references.include?(shared_store_ref)
  extension_target.source_build_phase.add_file_reference(shared_store_ref)
end

# Frameworks for the extension
extension_target.frameworks_build_phase.tap do |phase|
  existing = phase.files_references.map(&:path)
  unless existing.include?('System/Library/Frameworks/AuthenticationServices.framework')
    ref = project.frameworks_group.new_reference(
      'System/Library/Frameworks/AuthenticationServices.framework'
    )
    ref.source_tree = 'SDKROOT'
    phase.add_file_reference(ref)
  end
end

# ---------------------------------------------------------------------------
# 4. Build settings for the extension target.
# ---------------------------------------------------------------------------
dev_team = runner_target.build_configurations
                        .map { |c| c.build_settings['DEVELOPMENT_TEAM'] }
                        .compact.first

extension_target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = EXTENSION_BUNDLE_ID
  settings['PRODUCT_NAME']              = EXTENSION_NAME
  settings['INFOPLIST_FILE']            = "#{EXTENSION_NAME}/#{info_plist_path}"
  settings['CODE_SIGN_ENTITLEMENTS']    = "#{EXTENSION_NAME}/#{entitlements_path}"
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
  settings['TARGETED_DEVICE_FAMILY']     = '1,2'
  settings['SWIFT_VERSION']              = '5.0'
  settings['LD_RUNPATH_SEARCH_PATHS']    = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ]
  settings['SKIP_INSTALL'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = dev_team if dev_team
  settings['ENABLE_BITCODE'] = 'NO'
  settings['DEBUG_INFORMATION_FORMAT'] ||= config.name == 'Release' ? 'dwarf-with-dsym' : 'dwarf'
  settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'NO'
  # Version info – independent of Flutter's xcconfig (which is only
  # wired into the Runner target). Without these, CFBundleShortVersionString
  # and CFBundleVersion expand to empty strings and the OS rejects the
  # .appex bundle with "Invalid placeholder attributes".
  settings['MARKETING_VERSION']        = '1.0.1'
  settings['CURRENT_PROJECT_VERSION']  = '1'
  settings['VERSIONING_SYSTEM']        = 'apple-generic'
  # Keep using the hand-authored Info.plist rather than a generated one.
  settings['GENERATE_INFOPLIST_FILE']  = 'NO'
end

# ---------------------------------------------------------------------------
# 5. Embed the extension into the Runner app.
#
# The copy phase MUST sit before Flutter's `Thin Binary` script phase and
# the CocoaPods `[CP] Embed Pods Frameworks` / `[CP] Copy Pods Resources`
# phases, otherwise Xcode detects a dependency cycle between processing
# the Runner Info.plist and embedding the extension.
# ---------------------------------------------------------------------------
embed_phase = runner_target.copy_files_build_phases.find do |phase|
  phase.name == 'Embed Foundation Extensions'
end

unless embed_phase
  embed_phase = runner_target.new_copy_files_build_phase('Embed Foundation Extensions')
end
embed_phase.dst_subfolder_spec = '13' # PlugIns
embed_phase.symbol_dst_subfolder_spec = :plug_ins

# Reorder Runner build phases:
#   Sources, Frameworks, Resources, Embed Frameworks,
#   Embed Foundation Extensions   ← must come before Thin Binary
#   Thin Binary
#   [CP] Embed Pods Frameworks
#   [CP] Copy Pods Resources
runner_target.build_phases.delete(embed_phase)

thin_binary_index = runner_target.build_phases.index do |ph|
  ph.respond_to?(:name) && ph.display_name == 'Thin Binary'
end

embed_frameworks_index = runner_target.build_phases.index do |ph|
  ph.respond_to?(:name) && ph.display_name == 'Embed Frameworks'
end

insert_at = [thin_binary_index, embed_frameworks_index]
  .compact
  .min

if insert_at.nil?
  # Fallback: append if we can't locate the anchor phases.
  runner_target.build_phases << embed_phase
else
  # Insert just after "Embed Frameworks" if present, otherwise just
  # before "Thin Binary".
  target_index = if embed_frameworks_index
                   embed_frameworks_index + 1
                 else
                   thin_binary_index
                 end
  runner_target.build_phases.insert(target_index, embed_phase)
end

product_ref = extension_target.product_reference

unless embed_phase.files_references.include?(product_ref)
  build_file = embed_phase.add_file_reference(product_ref)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

# Target dependency so the extension builds before the app.
unless runner_target.dependencies.any? { |d| d.target == extension_target }
  runner_target.add_dependency(extension_target)
end

# ---------------------------------------------------------------------------
# 6. Save.
# ---------------------------------------------------------------------------
project.save

puts "✓ LumenPassAutoFill target wired into #{PROJECT_PATH}"
puts "  Bundle identifier: #{EXTENSION_BUNDLE_ID}"
puts "  App Group:         group.com.tranit.lumenpass"
puts ""
puts "Next steps:"
puts "  1. Open Runner.xcworkspace in Xcode."
puts "  2. Signing & Capabilities: for both 'Runner' and 'LumenPassAutoFill',"
puts "     enable 'App Groups' → group.com.tranit.lumenpass and"
puts "     'Keychain Sharing' → com.tranit.lumenpass.shared."
puts "  3. Add 'AutoFill Credential Provider' capability on the extension."
puts "  4. In Apple Developer Portal, register the App Group identifier"
puts "     if it's not already present, then regenerate provisioning profiles."
