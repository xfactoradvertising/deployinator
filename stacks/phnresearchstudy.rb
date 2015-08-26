module Deployinator
  module Stacks
    module Phnresearchstudy
      def phnresearchstudy_git_repo_url
        'git@github.com:xfactoradvertising/phnresearchstudy.git'
      end

      def phnresearchstudy_user
        'www-data'
      end

      def phnresearchstudy_stage_ip
        '52.25.81.13'
      end

      def phnresearchstudy_prod_ip
        '54.201.142.33'
      end

      def checkout_root
        '/tmp'
      end

      def site_root
        '/var/www/sites'
      end

      def site_path
        "#{site_root}/#{stack}"
      end

      def phnresearchstudy_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def phnresearchstudy_dev_version
        %x{cat #{site_path}/version.txt}
      end

      def phnresearchstudy_dev_build
        Version.get_build(phnresearchstudy_dev_version)
      end

      def phnresearchstudy_stage_version
        %x{ssh #{phnresearchstudy_user}@#{phnresearchstudy_stage_ip} 'cat #{site_path}/version.txt'}
      end

      def phnresearchstudy_stage_build
        Version.get_build(phnresearchstudy_stage_version)
      end

      def phnresearchstudy_prod_version
        %x{ssh #{phnresearchstudy_user}@#{phnresearchstudy_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def phnresearchstudy_prod_build
        Version.get_build(phnresearchstudy_prod_version)
      end

      def phnresearchstudy_head_build
        %x{git ls-remote #{phnresearchstudy_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def phnresearchstudy_dev
        old_build = phnresearchstudy_dev_build

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = phnresearchstudy_head_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan down --env=dev || true} # return true so command is non-fatal

          # sync relevant site files to final destination
          run_cmd %Q{rsync -av --delete --force --exclude='app/storage/*/**' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' --filter "protect .env*" --filter "protect down" --filter "protect vendor/**" --filter "protect app/storage/**" #{phnresearchstudy_git_checkout_path}/ #{site_path}}

           # ensure storage is writable (shouldn't have to do this but running webserver as different user)
          run_cmd %Q{chmod 777 #{site_path}/app/storage/*}

          # install dependencies
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install --no-dev}

          # run db migrations
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan migrate:refresh --seed --env=dev}

          # put application back online
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan up --env=dev}

          log_and_stream 'Done!<br>'
        rescue
          log_and_stream 'Failed!<br>'
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def phnresearchstudy_stage
        old_build = phnresearchstudy_stage_build

        build = phnresearchstudy_dev_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{phnresearchstudy_user}@#{phnresearchstudy_stage_ip} "cd #{site_path} && /usr/bin/php artisan down --env=stage || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='app/storage/*/**' --exclude='vendor/' --exclude='.env*' --filter "protect .env*" --filter "protect down" --filter "protect vendor/**" --filter "protect app/storage/**" #{site_path}/ #{phnresearchstudy_user}@#{phnresearchstudy_stage_ip}:#{site_path}}


          # TODO !!! add composer install !!!

          # install dependencies
          run_cmd %Q{ssh #{phnresearchstudy_user}@#{phnresearchstudy_stage_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # run db migrations
          run_cmd %Q{ssh #{phnresearchstudy_user}@#{phnresearchstudy_stage_ip} "cd #{site_path} && /usr/bin/php artisan migrate --seed --env=stage"}

          # put application back online
          run_cmd %Q{ssh #{phnresearchstudy_user}@#{phnresearchstudy_stage_ip} "cd #{site_path} && /usr/bin/php artisan up --env=stage"}

          log_and_stream 'Done!<br>'
        rescue
          log_and_stream 'Failed!<br>'
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'STAGE', :send_email => false) # TODO make email true

      end

      def phnresearchstudy_prod
        old_build = phnresearchstudy_prod_build
        build = phnresearchstudy_stage_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{phnresearchstudy_user}@#{phnresearchstudy_prod_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          # run_cmd %Q{ssh #{phnresearchstudy_user}@#{phnresearchstudy_stage_ip} "cd #{site_path} && rsync -ave ssh --delete --force --exclude='app/storage/*/**' --delete-excluded  --filter 'protect .env*' --filter 'protect down' --filter 'protect app/storage/**' --filter "protect app/files/**" --filter "protect public/assets/audio/**" #{site_path}/ #{reminders_user}@#{reminders_prod_ip}:#{site_path}"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --delete-excluded #{site_path} --filter "protect .env.php" --filter "protect down" #{phnresearchstudy_user}@#{phnresearchstudy_prod_ip}:#{site_path}}

          # run database migrations
          run_cmd %Q{ssh #{phnresearchstudy_user}@#{phnresearchstudy_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{phnresearchstudy_user}@#{phnresearchstudy_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{phnresearchstudy_user}@#{phnresearchstudy_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream 'Done!<br>'
        rescue
          log_and_stream 'Failed!<br>'
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def phnresearchstudy_environments
        [
          {
            :name => 'dev',
            :method => 'phnresearchstudy_dev',
            :current_version => phnresearchstudy_dev_version,
            :current_build => phnresearchstudy_dev_build,
            :next_build => phnresearchstudy_head_build
          },
          {
            :name => 'stage',
            :method => 'phnresearchstudy_stage',
            :current_version => phnresearchstudy_stage_version,
            :current_build => phnresearchstudy_stage_build,
            :next_build => phnresearchstudy_dev_build
          # },
          # {
          #   :name => 'prod',
          #   :method => 'phnresearchstudy_prod',
          #   :current_version => phnresearchstudy_prod_version,
          #   :current_build => phnresearchstudy_prod_build,
          #   :next_build => phnresearchstudy_stage_build
          # }        
        ]
      end
    end
  end
end
