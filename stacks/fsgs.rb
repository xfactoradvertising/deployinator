module Deployinator
  module Stacks
    module Fsgs
      def fsgs_git_repo_url
        "git@github.com:xfactoradvertising/com.fsgsresearch.git"
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

      def fsgs_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def fsgs_dev_version
        %x{cat #{fsgs_git_checkout_path}/version.txt}
      end

      def fsgs_dev_build
        Version.get_build(fsgs_dev_version)
      end

      def fsgs_head_build
        %x{git ls-remote #{fsgs_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def fsgs_dev(options={})
        old_build = Version.get_build(fsgs_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = fsgs_head_build

        begin
          # sync files to final destination
          run_cmd %Q{rsync -av --exclude='.git/' --exclude='.gitignore' #{fsgs_git_checkout_path}/ #{site_path}}
          # set permissions so webserver can write TODO setup passwordless sudo to chown&chmod instead? or
            # maybe set CAP_CHOWN for deployinator?
          # run_cmd %Q{chmod 777 #{site_path}/files}
          # run_cmd %Q{chmod 777 #{site_path}/app/storage/*}
          # run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install}
          # run_cmd %Q{cd #{site_path} && /usr/local/bin/composer dump-autoload}
          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def fsgs_environments
        [
          {
            :name => 'dev',
            :method => 'fsgs_dev',
            :current_version => fsgs_dev_version,
            :current_build => fsgs_dev_build,
            :next_build => fsgs_head_build
          }
        ]
      end
    end
  end
end