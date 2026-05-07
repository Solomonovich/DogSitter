require 'xcodeproj'

project_path = 'DogSitter.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Find the Views group
views_group = project.main_group.children.find { |g| g.display_name == 'Views' || g.name == 'Views' || g.path == 'Views' }
if views_group.nil?
  views_group = project.main_group.new_group('Views', 'Sources/Views')
end

file_path = 'Sources/Views/EditPostView.swift'
file_ref = views_group.files.find { |f| f.path == file_path || f.real_path.to_s.end_with?('EditPostView.swift') }

if file_ref.nil?
  file_ref = views_group.new_file('EditPostView.swift')
  puts "Added file reference for EditPostView.swift"
end

sources_build_phase = target.source_build_phase
if !sources_build_phase.files_references.include?(file_ref)
  sources_build_phase.add_file_reference(file_ref)
  puts "Added EditPostView.swift to compile sources"
end

project.save
puts "Project saved successfully"
