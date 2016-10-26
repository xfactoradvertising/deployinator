module Deployinator
  module Stacks
    module Smart5
      def smart5_git_repo_url
        "git@github.com:xfactoradvertising/smart.git"
      end

      def smart5_user
        'www-data'
      end

      def smart5_dev_ip
        '52.32.55.10'
      end

      def smart5_prod_ip
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

      def smart5_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def smart5_dev_version
        %x{ssh #{smart5_user}@#{smart5_dev_ip} 'cat #{site_path}/version.txt'}
      end

      def smart5_dev_build
        Version.get_build(smart5_dev_version)
      end

      def smart5_prod_version
        %x{ssh #{smart5_user}@#{smart5_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def smart5_prod_build
        Version.get_build(smart5_prod_version)
      end

      def smart5_head_build
        #%x{git ls-remote #{smart5_git_repo_url} HEAD | cut -c1-7}.chomp

        # NOTE explicitly getting smart5 branch HEAD revision here
        %x{git ls-remote #{smart5_git_repo_url} smart5 HEAD | tail -1 | cut -c1-7}.chomp
      end

      def smart5_dev(options={})
        old_build = smart5_dev_build

        git_cmd = old_build ? :git_freshen_clone_branch : :github_clone_branch
        send(git_cmd, stack, 'smart5', 'sh -c')

        git_bump_version stack, ''

        build = smart5_head_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{smart5_user}@#{smart5_dev_ip} "cd #{site_path} && /usr/bin/php artisan down --env=dev || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' --exclude='.env' --filter "protect .env" --filter "protect down" --filter "protect vendor/" --filter "protect storage/*/**" #{smart5_git_checkout_path}/ #{smart5_user}@#{smart5_dev_ip}:#{site_path}}

          # install dependencies
          run_cmd %Q{ssh #{smart5_user}@#{smart5_dev_ip} "cd #{site_path} && /usr/local/bin/composer install --no-dev"}

          # run db migrations
          run_cmd %Q{ssh #{smart5_user}@#{smart5_dev_ip} "cd #{site_path} && /usr/bin/php artisan migrate --seed --env=dev"}

          # put application back online
          run_cmd %Q{ssh #{smart5_user}@#{smart5_dev_ip} "cd #{site_path} && /usr/bin/php artisan up --env=dev"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'DEV', :send_email => false) # TODO make email true

      end

      def smart5_prod(options={})
        old_build = smart5_prod_build
        build = smart5_dev_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{smart5_user}@#{smart5_prod_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          run_cmd %Q{ssh #{smart5_user}@#{smart5_dev_ip} "rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='storage/*/**' --exclude='.env' --filter 'protect .env' --filter 'protect down' --filter 'protect storage/*/**' #{site_path}/ #{smart5_user}@#{smart5_prod_ip}:#{site_path}"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{smart5_user}@#{smart5_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # run database migrations
          run_cmd %Q{ssh #{smart5_user}@#{smart5_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force --seed"}

          # take application online
          run_cmd %Q{ssh #{smart5_user}@#{smart5_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def smart5_environments
        [
          {
            :name => 'dev',
            :method => 'smart5_dev',
            :current_version => smart5_dev_version,
            :current_build => smart5_dev_build,
            :next_build => smart5_head_build
          }#,
          # {
          #   :name => 'prod',
          #   :method => 'smart5_prod',
          #   :current_version => smart5_prod_version,
          #   :current_build => smart5_prod_build,
          #   :next_build => smart5_stage_build
          # }
        ]
      end
    end
  end
end
