require 'xcodeproj'

project_path = 'DogSitter.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

app_group = project.main_group.children.find { |g| g.display_name == 'App' || g.name == 'App' || g.path == 'App' }
if app_group.nil?
  app_group = project.main_group.new_group('App', 'Sources/App')
end

views_group = project.main_group.children.find { |g| g.display_name == 'Views' || g.name == 'Views' || g.path == 'Views' }
if views_group.nil?
  views_group = project.main_group.new_group('Views', 'Sources/Views')
end

cloudinary_ref = app_group.files.find { |f| f.path == 'Sources/App/CloudinaryHelper.swift' || f.real_path.to_s.end_with?('CloudinaryHelper.swift') }
if cloudinary_ref.nil?
  cloudinary_ref = app_group.new_file('CloudinaryHelper.swift')
end

picker_ref = views_group.files.find { |f| f.path == 'Sources/Views/ImagePicker.swift' || f.real_path.to_s.end_with?('ImagePicker.swift') }
if picker_ref.nil?
  picker_ref = views_group.new_file('ImagePicker.swift')
end

sources_build_phase = target.source_build_phase
sources_build_phase.add_file_reference(cloudinary_ref) unless sources_build_phase.files_references.include?(cloudinary_ref)
sources_build_phase.add_file_reference(picker_ref) unless sources_build_phase.files_references.include?(picker_ref)

project.save
puts "Added files to Xcode project"
