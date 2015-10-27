module Deployinator
  module Stacks
    module Recognitionstudy
      def recognitionstudy_git_repo_url
        "git@github.com:xfactoradvertising/recognitionstudy.git"
      end

      def recognitionstudy_prod_user
        'www-data'
      end

      def recognitionstudy_prod_ip
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

      def recognitionstudy_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def recognitionstudy_dev_version
        %x{cat #{recognitionstudy_git_checkout_path}/version.txt}
      end

      def recognitionstudy_dev_build
        Version.get_build(recognitionstudy_dev_version)
      end

      def recognitionstudy_prod_version
        %x{ssh #{recognitionstudy_prod_user}@#{recognitionstudy_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def recognitionstudy_prod_build
        Version.get_build(recognitionstudy_prod_version)
      end

      def recognitionstudy_head_build
        %x{git ls-remote #{recognitionstudy_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def recognitionstudy_dev(options={})
        old_build = Version.get_build(recognitionstudy_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = recognitionstudy_head_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan down --env=dev || true} # return true so command is non-fatal

          # sync site files to final destination
          run_cmd %Q{rsync -av --delete --force --exclude='app/storage/' --exclude='/vendor/' --exclude='.git/' --exclude='.gitignore' --filter "protect .env*" #{recognitionstudy_git_checkout_path}/ #{site_path}}

          # additionally sync top-level storage dirs (but not their contents)
          run_cmd %Q{rsync -lptgoDv --dirs --delete --force --exclude='.gitignore' #{recognitionstudy_git_checkout_path}/app/storage/ #{site_path}/app/storage}

          # ensure storage is writable (shouldn't have to do this but running webserver as different user)
          run_cmd %Q{chmod 777 #{site_path}/app/storage/*}

          # install dependencies (vendor dir was probably completely removed via above)
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install --no-dev}

          # run db migrations
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan migrate --seed --env=dev}

          # put application back online
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan up --env=dev}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def recognitionstudy_prod(options={})
        old_build = Version.get_build(recognitionstudy_prod_version)
        build = recognitionstudy_dev_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{recognitionstudy_prod_user}@#{recognitionstudy_prod_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --delete-excluded #{site_path} --filter "protect .env.php" --filter "protect down" #{recognitionstudy_prod_user}@#{recognitionstudy_prod_ip}:#{site_root}}

          # run database migrations
          run_cmd %Q{ssh #{recognitionstudy_prod_user}@#{recognitionstudy_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{recognitionstudy_prod_user}@#{recognitionstudy_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{recognitionstudy_prod_user}@#{recognitionstudy_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def recognitionstudy_environments
        [
          {
            :name => 'dev',
            :method => 'recognitionstudy_dev',
            :current_version => recognitionstudy_dev_version,
            :current_build => recognitionstudy_dev_build,
            :next_build => recognitionstudy_head_build
          },
          {
            :name => 'prod',
            :method => 'recognitionstudy_prod',
            :current_version => recognitionstudy_prod_version,
            :current_build => recognitionstudy_prod_build,
            :next_build => recognitionstudy_dev_build
          }        
        ]
      end
    end
  end
end
