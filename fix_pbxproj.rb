require 'xcodeproj'
project_path = 'DogSitter.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

chat_file_ref = project.files.find { |f| f.path =~ /ChatViews\.swift$/ }
views_group = chat_file_ref.parent

# Remove incorrect paths
bad_pre_walk = views_group.files.find { |f| f.path == 'Sources/Views/PreWalkView.swift' }
if bad_pre_walk
  target.source_build_phase.files_references.delete(bad_pre_walk)
  bad_pre_walk.remove_from_project
end

bad_walk_full = views_group.files.find { |f| f.path == 'Sources/Views/WalkFullView.swift' }
if bad_walk_full
  target.source_build_phase.files_references.delete(bad_walk_full)
  bad_walk_full.remove_from_project
end

# Add correct paths
pre_walk_ref = views_group.new_file('PreWalkView.swift')
target.source_build_phase.add_file_reference(pre_walk_ref)

walk_full_ref = views_group.new_file('WalkFullView.swift')
target.source_build_phase.add_file_reference(walk_full_ref)

project.save
puts "Fixed Xcode project paths"
