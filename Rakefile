# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |task|
  task.libs << 'test' << 'lib'
  task.test_files = FileList['test/**/*_test.rb']
  task.warning = true
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
rescue LoadError
  desc 'RuboCop is not installed'
  task :rubocop do
    warn 'RuboCop is not installed — run `bundle install` to lint.'
  end
end

task default: %i[test rubocop]
