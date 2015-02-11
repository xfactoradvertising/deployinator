module Deployinator
  module Stacks
    module Smartdev
      def smartdev_git_repo_url
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

      def smartdev_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def smartdev_dev_version
        %x{cat #{smartdev_git_checkout_path}/version.txt}
      end

      def smartdev_dev_build
        Version.get_build(smartdev_dev_version)
      end

      def smartdev_head_build
        # NOTE explicitly getting branch HEAD revision here (could move to a helper)
        %x{git ls-remote #{smartdev_git_repo_url} dev HEAD | tail -1 | cut -c1-7}.chomp
        #{}%x{git ls-remote #{smartdev_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def smartdev_dev(options={})
        old_build = Version.get_build(smartdev_dev_version)

        git_cmd = old_build ? :git_freshen_clone_branch : :github_clone_branch
        send(git_cmd, stack, 'dev', 'sh -c')

        git_bump_version stack, ''

        build = smartdev_head_build

        begin
          # TODO check for zip files in app/views or app/controllers (or app/* ?) and fail..these break composer dump-autoload

          # take site offline for deployment
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan down || true} # return true so command is non-fatal

          # sync files to final destination
          run_cmd %Q{rsync -av --delete --force --exclude='app/storage/' --exclude='public/assets/audio/' --exclude='public/assets/files/' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' #{smartdev_git_checkout_path}/ #{site_path}}

          # set permissions so webserver can write TODO setup passwordless sudo to chown&chmod instead? or
            # maybe set CAP_CHOWN for deployinator?
          run_cmd %Q{chmod 777 #{site_path}/app/storage/}
          run_cmd %Q{chmod 777 #{site_path}/public/assets/audio}
          run_cmd %Q{chmod 777 #{site_path}/public/assets/files}

          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install  --no-dev}

          #probably don't need this..use post-install-cmd to clear and optimize instead
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer dump-autoload}

          # run db migrations
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan migrate --env=dev}

          # take site back online
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan up}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def smartdev_environments
        [
          {
            :name => 'dev',
            :method => 'smartdev_dev',
            :current_version => smartdev_dev_version,
            :current_build => smartdev_dev_build,
            :next_build => smartdev_head_build
          }        
        ]
      end
    end
  end
end