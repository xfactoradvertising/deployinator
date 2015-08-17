module Deployinator
  module Stacks
    module Reminders
      def reminders_git_repo_url
        "git@github.com:xfactoradvertising/bearded-dangerzone.git"
      end

      def reminders_user
        'www-data'
      end

      def reminders_stage_ip
        '52.25.81.13'
      end

      def reminders_prod_ip
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

      def reminders_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def reminders_stage_version
        %x{ssh #{reminders_user}@#{reminders_stage_ip} 'cat #{site_path}/version.txt'}
      end

      def reminders_stage_build
        Version.get_build(reminders_stage_version)
      end

      def reminders_prod_version
        %x{ssh #{reminders_user}@#{reminders_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def reminders_prod_build
        Version.get_build(reminders_prod_version)
      end

      def reminders_head_build
        %x{git ls-remote #{reminders_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def reminders_stage(options={})
        old_build = reminders_stage_build

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = reminders_head_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{reminders_user}@#{reminders_stage_ip} "cd #{site_path} && /usr/bin/php artisan down --env=stage || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='/storage/' --exclude='/vendor/' --exclude='.git/' --exclude='.gitignore' --filter "protect .env" --filter "protect down" --filter "protect vendor/" --filter "protect storage/**" #{reminders_git_checkout_path}/ #{reminders_user}@#{reminders_stage_ip}:#{site_path}}

          # install dependencies
          run_cmd %Q{ssh #{reminders_user}@#{reminders_stage_ip} "cd #{site_path} && /usr/local/bin/composer install --no-dev"}

          # run db migrations
          run_cmd %Q{ssh #{reminders_user}@#{reminders_stage_ip} "cd #{site_path} && /usr/bin/php artisan migrate --seed --env=stage"}

          # put application back online
          run_cmd %Q{ssh #{reminders_user}@#{reminders_stage_ip} "cd #{site_path} && /usr/bin/php artisan up --env=stage"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'STAGE', :send_email => false) # TODO make email true

      end

      def reminders_prod(options={})
        old_build = reminders_prod_build
        build = reminders_stage_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{reminders_user}@#{reminders_stage_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          run_cmd %Q{ssh #{reminders_user}@#{reminders_stage_ip} "rsync -ave ssh --delete --force --exclude='app/storage/*' --delete-excluded #{site_path} --filter 'protect .env.php' --filter 'protect down' --filter 'protect app/storage/*' #{site_path}/ #{reminders_user}@#{reminders_prod_ip}:#{site_path}"}

          # run database migrations
          run_cmd %Q{ssh #{reminders_user}@#{reminders_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{reminders_user}@#{reminders_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{reminders_user}@#{reminders_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def reminders_environments
        [
          {
            :name => 'stage',
            :method => 'reminders_stage',
            :current_version => reminders_stage_version,
            :current_build => reminders_stage_build,
            :next_build => reminders_head_build
          },
          {
            :name => 'prod',
            :method => 'reminders_prod',
            :current_version => reminders_prod_version,
            :current_build => reminders_prod_build,
            :next_build => reminders_stage_build
          }        
        ]
      end
    end
  end
end
