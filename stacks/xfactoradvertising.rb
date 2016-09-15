module Deployinator
  module Stacks
    module Xfactoradvertising
      def xfactoradvertising_git_repo_url
        "git@github.com:xfactoradvertising/xfactoradvertising.git"
      end

      def xfactoradvertising_prod_user
        'www-data'
      end

      def xfactoradvertising_prod_ip
        '54.201.142.33'
      end

      def xfactoradvertising_stage_ip
        '52.25.81.13'
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

      def xfactoradvertising_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def xfactoradvertising_staging_version
        %x{cat #{xfactoradvertising_git_checkout_path}/version.txt}
      end

      def xfactoradvertising_staging_build
        Version.get_build(xfactoradvertising_staging_version)
      end

      def xfactoradvertising_prod_version
        %x{ssh #{xfactoradvertising_prod_user}@#{xfactoradvertising_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def xfactoradvertising_prod_build
        Version.get_build(xfactoradvertising_prod_version)
      end

      def xfactoradvertising_head_build
        %x{git ls-remote #{xfactoradvertising_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def stage_cmd cmd_in
        run_cmd %Q{ ssh www-data@52.25.81.13 \"cd #{site_path} && #{ cmd_in }\" }
      end

      def xfactoradvertising_staging(options={})
        old_build = Version.get_build(xfactoradvertising_staging_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = xfactoradvertising_head_build

        begin
          stage_cmd "/usr/bin/php artisan down --env=stage || true"

          stage_cmd "rsync -av --delete --force --exclude='app/storage/' --exclude='/vendor/' --exclude='.git/' --exclude='.gitignore' /tmp/xfactoradvertising/ #{site_path}"

          # additionally sync top-level storage dirs (but not their contents)
          stage_cmd "rsync -lptgoDv --dirs --delete --force --exclude='.gitignore' /tmp/xfactoradvertising/app/storage/ #{site_path}/app/storage"

          stage_cmd "/usr/local/bin/composer install --no-dev"

          stage_cmd "/usr/bin/php artisan up --env=stage"

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true
      end

      def xfactoradvertising_prod(options={})
        old_build = Version.get_build(xfactoradvertising_prod_version)
        build = xfactoradvertising_staging_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{ssh #{xfactoradvertising_prod_user}@#{xfactoradvertising_prod_ip} "cd #{site_path} && /usr/bin/php artisan down || true"} # return true so command is non-fatal (artisan doesn't exist the first time)

          # TODO figure out how to keep from deleting xfactoradvertising/app/storage/meta/down (which enables the site)

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --delete-excluded #{site_path} #{xfactoradvertising_prod_user}@#{xfactoradvertising_prod_ip}:#{site_root}}

          # run database migrations
          #run_cmd %Q{ssh #{xfactoradvertising_prod_user}@#{xfactoradvertising_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{xfactoradvertising_prod_user}@#{xfactoradvertising_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{xfactoradvertising_prod_user}@#{xfactoradvertising_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def xfactoradvertising_environments
        [
          {
            :name => 'staging',
            :method => 'xfactoradvertising_staging',
            :current_version => xfactoradvertising_staging_version,
            :current_build => xfactoradvertising_staging_build,
            :next_build => xfactoradvertising_head_build
          },
          {
            :name => 'prod',
            :method => 'xfactoradvertising_prod',
            :current_version => xfactoradvertising_prod_version,
            :current_build => xfactoradvertising_prod_build,
            :next_build => xfactoradvertising_staging_build
          }        
        ]
      end
    end
  end
end
