module Deployinator
  module Stacks
    module Studyfootulcers
      def studyfootulcers_git_repo_url
        "git@github.com:xfactoradvertising/com.studyfootulcers.git"
      end

      def prod_user
        'ubuntu'
      end

      def prod_ip
        '10.248.3.116'
      end

      def checkout_root
        "/tmp"
      end

      def site_root
        '/var/www/sites'
      end

      def site_path
        "#{site_root}/#{stack}"
      end

      def studyfootulcers_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def studyfootulcers_dev_version
        %x{cat #{studyfootulcers_git_checkout_path}/version.txt}
      end

      def studyfootulcers_dev_build
        Version.get_build(studyfootulcers_dev_version)
      end

      def studyfootulcers_prod_version
        %x{ssh #{prod_user}@#{prod_ip} 'cat #{site_path}/version.txt'}
      end

      def studyfootulcers_prod_build
        Version.get_build(studyfootulcers_prod_version)
      end

      def studyfootulcers_head_build
        %x{git ls-remote #{studyfootulcers_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def studyfootulcers_dev(options={})
        old_build = Version.get_build(studyfootulcers_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = studyfootulcers_head_build

        begin
          # sync files to final destination
          run_cmd %Q{rsync -av --delete --force --delete-excluded --exclude='.git/' --exclude='.gitignore' #{studyfootulcers_git_checkout_path}/ #{site_path}}

          # set design mode
          run_cmd %Q{curl -s -o /dev/null "http://studyfootulcers.xfactordevelopment.com/?reload=design"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def studyfootulcers_prod(options={})
        old_build = Version.get_build(studyfootulcers_prod_version)
        build = studyfootulcers_dev_build

        begin
          run_cmd %Q{rsync -ave ssh --delete --force --delete-excluded #{site_path} #{prod_user}@#{prod_ip}:#{site_root}}

          # reload site (ensure settings/environment files are correct)
          run_cmd %Q{curl -s -o /dev/null "http://www.studyfootulcers.com/?reload=true"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def studyfootulcers_environments
        [
          {
            :name => 'dev',
            :method => 'studyfootulcers_dev',
            :current_version => studyfootulcers_dev_version,
            :current_build => studyfootulcers_dev_build,
            :next_build => studyfootulcers_head_build
          },
          {
            :name => 'prod',
            :method => 'studyfootulcers_prod',
            :current_version => studyfootulcers_prod_version,
            :current_build => studyfootulcers_prod_build,
            :next_build => studyfootulcers_dev_build
          }         
        ]
      end
    end
  end
end