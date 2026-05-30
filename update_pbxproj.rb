require 'xcodeproj'
project_path = 'DogSitter.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Find the group that contains ChatViews.swift
chat_file_ref = project.files.find { |f| f.path =~ /ChatViews\.swift$/ }
views_group = chat_file_ref.parent

if views_group
  # Remove WalkViews.swift
  file_ref = views_group.files.find { |f| f.path =~ /WalkViews\.swift$/ }
  if file_ref
    target.source_build_phase.files_references.delete(file_ref)
    file_ref.remove_from_project
  end

  # Add PreWalkView.swift
  pre_walk_ref = views_group.new_file('Sources/Views/PreWalkView.swift')
  target.source_build_phase.add_file_reference(pre_walk_ref)

  # Add WalkFullView.swift
  walk_full_ref = views_group.new_file('Sources/Views/WalkFullView.swift')
  target.source_build_phase.add_file_reference(walk_full_ref)

  project.save
  puts "Updated Xcode project successfully"
else
  puts "Views group not found!"
end
