##############################################################################
# Gem Management
##############################################################################

require "rake"
require "rake/clean"
require "rake/gempackagetask"
require "rake/rdoctask"
require "fileutils"
 
include FileUtils
 
CLEAN.include ["**/.*.sw?", "pkg/*", ".config", "doc/*", "coverage/*"]


##############################################################################
# Load Gemspec Data
##############################################################################

gemspec_data = File.read("sequel_nested_set.gemspec")
spec = nil
Thread.new { spec = eval("$SAFE = 3\n#{gemspec_data}") }.join
 
desc "Packages up the Sequel Plugin: #{spec.name}."
task :default => [:package]
task :package => [:clean]
 
task :doc => [:rdoc]

##############################################################################
# RDoc Task
##############################################################################

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = "doc/rdoc"
  rdoc.options += spec.rdoc_options
  rdoc.main = "README"
  rdoc.title = spec.name
  rdoc.rdoc_files.add ["lib/*.rb", "lib/**/*.rb"]
  rdoc.rdoc_files.add spec.extra_rdoc_files
end
 
Rake::GemPackageTask.new(spec) do |p|
  p.need_tar = true
  p.gem_spec = spec
end


##############################################################################
# Rubyforge Managment Tasks
##############################################################################

task :release => [:package] do
  sh %{rubyforge login}
  sh %{rubyforge add_release sequel #{spec.name} #{Version} pkg/#{spec.name}-#{spec.version}.tgz}
  sh %{rubyforge add_file sequel #{spec.name} #{Version} pkg/#{spec.name}-#{spec.version}.gem}
end
 
task :install do
  sh %{rake package}
  sh %{sudo gem install pkg/#{spec.name}-#{spec.version}.gem}
end
 
task :install_no_docs do
  sh %{rake package}
  sh %{sudo gem install pkg/#{spec.name}-#{spec.version}.gem --no-rdoc --no-ri}
end
 
task :uninstall => [:clean] do
  sh %{sudo gem uninstall #{spec.name}}
end
 
desc "Update docs and upload to rubyforge.org"
task :doc_rforge do
  sh %{rake doc}
  sh %{scp -r doc/rdoc/* ciconia@rubyforge.org:/var/www/gforge-projects/sequel/plugins/#{spec.name}}
end
 
##############################################################################
# rSpec
##############################################################################
 
require "spec/rake/spectask"
 
desc "Run specs with coverage"
Spec::Rake::SpecTask.new("spec") do |spec_task|
  spec_task.spec_opts = File.read("spec/spec.opts").split("\n")
  spec_task.spec_files = FileList["spec/*_spec.rb"].sort
  spec_task.rcov = true
  spec_task.rcov_opts = lambda do
    IO.readlines("spec/rcov.opts").map {|l| l.chomp.split " "}.flatten
  end
end
 
desc "Run specs without coverage"
Spec::Rake::SpecTask.new("spec_no_cov") do |spec_task|
  spec_task.spec_opts = File.read("spec/spec.opts").split("\n")
  spec_task.spec_files = FileList["spec/*_spec.rb"].sort
end
 
desc "Run all specs with coverage"
Spec::Rake::SpecTask.new("specs") do |spec_task|
  spec_task.spec_opts = File.read("spec/spec.opts").split("\n")
  spec_task.spec_files = FileList["spec/**/*_spec.rb"].sort
  spec_task.rcov = true
  spec_task.rcov_opts = lambda do
    IO.readlines("spec/rcov.opts").map {|l| l.chomp.split " "}.flatten
  end
end
 
desc "Run all specs without coverage"
Spec::Rake::SpecTask.new("specs_no_cov") do |spec_task|
  spec_task.spec_opts = File.read("spec/spec.opts").split("\n")
  spec_task.spec_files = FileList["spec/**/*_spec.rb"].sort
end
 
desc "Run all specs and output html"
Spec::Rake::SpecTask.new("specs_html") do |spec_task|
  spec_task.spec_opts = ["--format", "html"]
  spec_task.spec_files = Dir["spec/**/*_spec.rb"].sort
end
 
##############################################################################
# Statistics
##############################################################################
 
STATS_DIRECTORIES = [
  %w(Code lib/),
  %w(Spec spec/)
].collect { |name, dir| [ name, "./#{dir}" ] }.select { |name, dir| File.directory?(dir) }
 
desc "Report code statistics (KLOCs, etc) from the application"
task :stats do
  require "extra/stats"
  verbose = true
  CodeStatistics.new(*STATS_DIRECTORIES).to_s
end
