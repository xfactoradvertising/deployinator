module Deployinator
  module Stacks
    module Endostudynow
      def endostudynow_git_repo_url
        "git@github.com:xfactoradvertising/endostudynow.git"
      end

      def endostudynow_user
        'www-data'
      end

      def endostudynow_stage_ip
        '52.25.81.13'
      end

      def endostudynow_prod_ip
        '54.201.142.33'
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

      def endostudynow_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def endostudynow_stage_version
        %x{ssh #{endostudynow_user}@#{endostudynow_stage_ip} 'cat #{site_path}/version.txt'}
      end

      def endostudynow_stage_build
        Version.get_build(endostudynow_stage_version)
      end

      def endostudynow_prod_version
        %x{ssh #{endostudynow_user}@#{endostudynow_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def endostudynow_prod_build
        Version.get_build(endostudynow_prod_version)
      end

      def endostudynow_head_build
        %x{git ls-remote #{endostudynow_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def endostudynow_stage(options={})
        old_build = endostudynow_stage_build

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = endostudynow_head_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_stage_ip} "cd #{site_path} && /usr/bin/php artisan down --env=stage || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='app/storage/*' #{endostudynow_git_checkout_path} --exclude='/vendor/' --exclude='.git/' --exclude='.gitignore' --filter "protect .env.stage.php" --filter "protect down" --filter "protect endostudynow/vendor/" #{endostudynow_user}@#{endostudynow_stage_ip}:#{site_root}}

          # additionally sync top-level storage dirs (but not their contents)
          run_cmd %Q{rsync -lptgoDve ssh --dirs --delete --force --exclude='.gitignore' #{endostudynow_git_checkout_path}/app/storage/ #{endostudynow_user}@#{endostudynow_stage_ip}:#{site_path}/app/storage}

          # install dependencies
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_stage_ip} "cd #{site_path} && /usr/local/bin/composer install --no-dev"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_stage_ip} "cd #{site_path} && /usr/bin/php artisan dump-autoload --env=stage"}

          # run db migrations
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_stage_ip} "cd #{site_path} && /usr/bin/php artisan migrate --env=stage"}

          # put application back online
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_stage_ip} "cd #{site_path} && /usr/bin/php artisan up --env=stage"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'STAGE', :send_email => false) # TODO make email true

      end

      def endostudynow_prod(options={})
        old_build = Version.get_build(endostudynow_prod_version)
        build = endostudynow_stage_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_stage_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_stage_ip} "cd #{site_path} && rsync -ave ssh --delete --force --exclude='app/storage/*' --delete-excluded #{site_path} --filter 'protect .env.php' --filter 'protect down' --filter 'protect app/storage/*' #{endostudynow_user}@#{endostudynow_prod_ip}:#{site_root}"}

          # # additionally sync top-level storage dirs (but not their contents)
          # run_cmd %Q{rsync -lptgoDve ssh --dirs --delete --force --exclude='.gitignore' #{endostudynow_git_checkout_path}/app/storage/ #{endostudynow_user}@#{endostudynow_prod_ip}:#{site_path}/app/storage}

          # run database migrations
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{endostudynow_user}@#{endostudynow_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def endostudynow_environments
        [
          {
            :name => 'stage',
            :method => 'endostudynow_stage',
            :current_version => endostudynow_stage_version,
            :current_build => endostudynow_stage_build,
            :next_build => endostudynow_head_build
          },
          {
            :name => 'prod',
            :method => 'endostudynow_prod',
            :current_version => endostudynow_prod_version,
            :current_build => endostudynow_prod_build,
            :next_build => endostudynow_stage_build
          }        
        ]
      end
    end
  end
end
