require 'xcodeproj'

project_path = 'DogSitter.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first # DogSitter

# Find the Services group
services_group = project.main_group.children.find { |g| g.display_name == 'Services' || g.name == 'Services' || g.path == 'Services' }
if services_group.nil?
  services_group = project.main_group.new_group('Services', 'Sources/Services')
end

# Check if the file already exists in the group to avoid duplicates
file_path = 'Sources/Services/AuthHelpers.swift'
file_ref = services_group.files.find { |f| f.path == file_path || f.real_path.to_s.end_with?('AuthHelpers.swift') }

if file_ref.nil?
  # Create the file reference
  file_ref = services_group.new_file('AuthHelpers.swift')
  puts "Added file reference for AuthHelpers.swift"
else
  puts "File reference already exists"
end

# Add the file to the target's source build phase
sources_build_phase = target.source_build_phase
if !sources_build_phase.files_references.include?(file_ref)
  build_file = sources_build_phase.add_file_reference(file_ref)
  puts "Added AuthHelpers.swift to compile sources"
else
  puts "AuthHelpers.swift is already in compile sources"
end

# Find any stray 'App/AuthHelpers.swift' references and remove them
stray_refs = project.files.select { |f| f.real_path.to_s.end_with?('App/AuthHelpers.swift') }
stray_refs.each do |ref|
  ref.remove_from_project
  puts "Removed stray reference: #{ref.path}"
end

project.save
puts "Project saved successfully"
