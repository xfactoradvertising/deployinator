module Deployinator
  module Stacks
    module Smart
      def smart_git_repo_url
        "git@github.com:xfactoradvertising/smart.git"
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

      def smart_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def smart_dev_version
        %x{cat #{smart_git_checkout_path}/version.txt}
      end

      def smart_dev_build
        Version.get_build(smart_dev_version)
      end

      def smart_head_build
        %x{git ls-remote #{smart_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def smart_dev(options={})
        old_build = Version.get_build(smart_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        # "/Users/jguice/Development/xfactor/deployinator/helpers.rb:66:in `run_cmd'", "/Users/jguice/Development/xfactor/deployinator/helpers/git.rb:27:in `git_clone'", "/Users/jguice/Development/xfactor/deployinator/helpers/git.rb:23:in `github_clone'", "/Users/jguice/Development/xfactor/deployinator/stacks/smart.rb:32:in `smart_dev'", 

        # Running sh -c 'cd /tmp && git clone https://github.com/xfactoradvertising/smart.git smart'


        git_bump_version stack, ''

        build = smart_head_build

        begin
          # TODO check for zip files in app/views or app/controllers (or app/* ?) and fail..these break composer dump-autoload
          # sync files to final destination
          run_cmd %Q{rsync -av #{smart_git_checkout_path}/ #{site_path}}
          # set permissions so webserver can write TODO setup passwordless sudo to chown&chmod instead? or
            # maybe set CAP_CHOWN for deployinator?
          run_cmd %Q{chmod 777 #{site_path}/files}
          run_cmd %Q{chmod 777 #{site_path}/app/storage/*}
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer dump-autoload}
          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

        #log_and_stream "Fill in the smart_production method in stacks/smart.rb!<br>"

        # log the deploy
        #log_and_shout :old_build => environments[0][:current_build].call, :build => environments[0][:next_build].call

        # demo version of above
        # old_build = Version.get_build(demo_production_version)

        # git_cmd = old_build ? :git_freshen_clone : :github_clone
        # send(git_cmd, stack, "sh -c")

        # git_bump_version stack, ""

        # build = demo_head_build

        # begin
        #   run_cmd %Q{echo "ssh host do_something"}
        #   log_and_stream "Done!<br>"
        # rescue
        #   log_and_stream "Failed!<br>"
        # end

        # # log this deploy / timing
        # log_and_shout(:old_build => old_build, :build => build, :send_email => true)
      end

      def smart_environments
        [
          {
            :name => 'dev',
            :method => 'smart_dev',
            :current_version => smart_dev_version,
            :current_build => smart_dev_build,
            :next_build => smart_head_build
          }
        ]
      end
    end
  end
end