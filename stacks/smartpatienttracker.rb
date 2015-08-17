module Deployinator
  module Stacks
    module Smartpatienttracker
      def smartpatienttracker_git_repo_url
        "git@github.com:xfactoradvertising/smart.git"
      end

      def smartpatienttracker_user
        'www-data'
      end

      def smartpatienttracker_stage_ip
        '52.25.81.13'
      end

      def smartpatienttracker_prod_ip
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

      def smartpatienttracker_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def smartpatienttracker_dev_version
        %x{cat #{smartpatienttracker_git_checkout_path}/version.txt}
      end

      def smartpatienttracker_dev_build
        Version.get_build(smartpatienttracker_dev_version)
      end

      def smartpatienttracker_stage_version
        %x{ssh #{smartpatienttracker_user}@#{smartpatienttracker_stage_ip} 'cat #{site_path}/version.txt'}
      end

      def smartpatienttracker_stage_build
        Version.get_build(smartpatienttracker_stage_version)
      end

      def smartpatienttracker_prod_version
        %x{ssh #{smartpatienttracker_user}@#{smartpatienttracker_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def smartpatienttracker_prod_build
        Version.get_build(smartpatienttracker_prod_version)
      end

      def smartpatienttracker_head_build
        %x{git ls-remote #{smartpatienttracker_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def smartpatienttracker_dev(options={})
        old_build = Version.get_build(smartpatienttracker_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = smartpatienttracker_head_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan down --env=dev || true} # return true so command is non-fatal

          # sync relevant site files to final destination
          run_cmd %Q{rsync -av --delete --force --exclude='app/storage/*/**' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' --filter "protect .env*" --filter "protect down" --filter "protect vendor/**" --filter "protect app/storage/**" #{smartpatienttracker_git_checkout_path}/ #{site_path}}

           # ensure storage is writable (shouldn't have to do this but running webserver as different user)
          run_cmd %Q{chmod 777 #{site_path}/app/storage/*}

          # install dependencies
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install --no-dev}

          # run db migrations
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan migrate:refresh --seed --env=dev}

          # put application back online
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan up --env=dev}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def smartpatienttracker_stage(options={})
        old_build = smartpatienttracker_stage_build

        build = smartpatienttracker_dev_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{smartpatienttracker_user}@#{smartpatienttracker_stage_ip} "cd #{site_path} && /usr/bin/php artisan down --env=stage || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='app/storage/*/**' --exclude='vendor/' --exclude='.env*' --filter "protect .env*" --filter "protect down" --filter "protect vendor/**" --filter "protect app/storage/**" #{site_path}/ #{smartpatienttracker_user}@#{smartpatienttracker_stage_ip}:#{site_path}}

          # install dependencies
          run_cmd %Q{ssh #{smartpatienttracker_user}@#{smartpatienttracker_stage_ip} "cd #{site_path} && /usr/local/bin/composer install --no-dev"}

          # run db migrations
          run_cmd %Q{ssh #{smartpatienttracker_user}@#{smartpatienttracker_stage_ip} "cd #{site_path} && /usr/bin/php artisan migrate --seed --env=stage"}

          # put application back online
          run_cmd %Q{ssh #{smartpatienttracker_user}@#{smartpatienttracker_stage_ip} "cd #{site_path} && /usr/bin/php artisan up --env=stage"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'STAGE', :send_email => false) # TODO make email true

      end

      def smartpatienttracker_prod(options={})
        old_build = Version.get_build(smartpatienttracker_prod_version)
        build = smartpatienttracker_dev_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{smartpatienttracker_user}@#{smartpatienttracker_prod_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          # run_cmd %Q{ssh #{smartpatienttracker_user}@#{smartpatienttracker_stage_ip} "cd #{site_path} && rsync -ave ssh --delete --force --exclude='app/storage/*/**' --delete-excluded  --filter 'protect .env*' --filter 'protect down' --filter 'protect app/storage/**' #{site_path}/ #{reminders_user}@#{reminders_prod_ip}:#{site_path}"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --delete-excluded #{site_path} --filter "protect .env.php" --filter "protect down" #{smartpatienttracker_user}@#{smartpatienttracker_prod_ip}:#{site_path}}

          # run database migrations
          run_cmd %Q{ssh #{smartpatienttracker_user}@#{smartpatienttracker_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{smartpatienttracker_user}@#{smartpatienttracker_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{smartpatienttracker_user}@#{smartpatienttracker_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def smartpatienttracker_environments
        [
          {
            :name => 'dev',
            :method => 'smartpatienttracker_dev',
            :current_version => smartpatienttracker_dev_version,
            :current_build => smartpatienttracker_dev_build,
            :next_build => smartpatienttracker_head_build
          },
          {
            :name => 'stage',
            :method => 'smartpatienttracker_stage',
            :current_version => smartpatienttracker_stage_version,
            :current_build => smartpatienttracker_stage_build,
            :next_build => smartpatienttracker_head_build
          },
          {
            :name => 'prod',
            :method => 'smartpatienttracker_prod',
            :current_version => smartpatienttracker_prod_version,
            :current_build => smartpatienttracker_prod_build,
            :next_build => smartpatienttracker_dev_build
          }        
        ]
      end
    end
  end
end
