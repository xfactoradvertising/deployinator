# Stolen from github.com/defunkt/mustache

require 'rake/testtask'

#
# Helpers
#

def command?(command)
  system("type #{command} &> /dev/null")
end


#
# Tests
#

task :default => :test

Rake::TestTask.new do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
end


#
# Stacks
#

desc "Create a new deployinator stack. usage: STACK=my_blog rake new_stack"
task :new_stack do
  require 'mustache/sinatra'
  stack = ENV['STACK']
  raise "You must supply a stack name (like STACK=foo rake new_stack)" unless stack
  raise "Already exists" if File.exists?("./stacks/#{stack}.rb")
  
  File.open("./stacks/#{stack}.rb", "w") do |f|
    contents = <<-EOF
module Deployinator
  module Stacks
    module #{Mustache.classify(stack)}
      def #{stack}_production_version
        # %x{curl http://my-app.com/version.txt}
        "cf44aab-20110729-230910-UTC"
      end

      def #{stack}_head_build
        # the build version you're about to push
        # %x{git ls-remote #\{your_git_repo_url\} HEAD | cut -c1-7}.chomp
        "11666e3"
      end

      def #{stack}_production(options={})
        log_and_stream "Fill in the #{stack}_production method in stacks/#{stack}.rb!<br>"

        # log the deploy
        log_and_shout :old_build => environments[0][:current_build].call, :build => environments[0][:next_build].call
      end
    end
  end
end
    EOF
    f.print contents
  end

  File.open("./templates/#{stack}.mustache", "w") do |f|
    f.print "{{< generic_single_push }}"
  end
  
  puts "Created #{stack}!\nEdit stacks/#{stack}.rb##{stack}_production to do your bidding"
end

# TODO just have a single task "new_stack" that takes an argument (the template to use) then change the above task to just be a default.erb template
desc "Create a new laravel 5 ('blueprint2') stack. usage: STACK=mysite rake new_laravel5_stack"
task :new_laravel5_stack do

  require 'mustache/sinatra'
  require 'io/console'

  stack = ENV['STACK']
  raise "You must supply a stack name (like STACK=foo rake new_stack)" unless stack
  if File.exists?("./stacks/#{stack}.rb")
    print "Stack #{stack} already exists.  Overwrite? (y/n): "
    clobber = STDIN.getch

    unless clobber.downcase == 'y'
      puts "aborted."
      exit 1
    end
  end


  require 'erb'

  stack_template = File.join(File.dirname(__FILE__), 'stack_templates', 'laravel5.erb')

  begin
    template = File.read(stack_template)
  rescue Errno::ENOENT
    raise(ArgumentError, "couldn't find #{stack_template}")
  end

  rendering = ERB.new(template,nil,'>-<>').result(binding)  # => "Hello World"

  File.open("./stacks/#{stack}.rb", "w") do |f|
    f.puts(rendering)
  end

  File.open("./templates/#{stack}.mustache", "w") do |f|
    f.print "{{< generic_single_push }}"
  end
  
  puts "Created #{stack}!\nEdit stacks/#{stack}.rb to alter the behavior."
end

#
# Documentation
# A github page at some point
#

desc "Publish to GitHub Pages"
task :pages => [ "man:build" ] do
  Dir['man/*.html'].each do |f|
    cp f, File.basename(f).sub('.html', '.newhtml')
  end

  `git commit -am 'generated manual'`
  `git checkout site`

  Dir['*.newhtml'].each do |f|
    mv f, f.sub('.newhtml', '.html')
  end

  `git add .`
  `git commit -m updated`
  `git push site site:master`
  `git checkout master`
  puts :done
end
