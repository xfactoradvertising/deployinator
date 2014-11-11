module Deployinator
  module Stacks
    module Migrainestudynow
      def migrainestudynow_git_repo_url
        "git@github.com:xfactoradvertising/migrainestudynow.git"
      end

      def migrainestudynow_prod_user
        'www-data'
      end

      def migrainestudynow_prod_ip
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

      def migrainestudynow_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def migrainestudynow_dev_version
        %x{cat #{migrainestudynow_git_checkout_path}/version.txt}
      end

      def migrainestudynow_dev_build
        Version.get_build(migrainestudynow_dev_version)
      end

      def migrainestudynow_prod_version
        %x{ssh #{migrainestudynow_prod_user}@#{migrainestudynow_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def migrainestudynow_prod_build
        Version.get_build(migrainestudynow_prod_version)
      end

      def migrainestudynow_head_build
        %x{git ls-remote #{migrainestudynow_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def migrainestudynow_dev(options={})
        old_build = Version.get_build(migrainestudynow_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = migrainestudynow_head_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan down || true} # return true so command is non-fatal

          # sync site files to final destination
          run_cmd %Q{rsync -av --delete --force --exclude='app/storage/' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' #{migrainestudynow_git_checkout_path}/ #{site_path}}

          # additionally sync top-level storage dirs (but not their contents)
          run_cmd %Q{rsync -rlptgoDv --delete --force --exclude='.gitignore' #{migrainestudynow_git_checkout_path}/app/storage/ #{site_path}/app/storage}

          # ensure storage is writable (shouldn't have to do this but running webserver as different user)
          run_cmd %Q{chmod 777 #{site_path}/app/storage/*}

          # install dependencies (vendor dir was probably completely removed via above)
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install --no-dev}

          # run db migrations
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan migrate || true} # TODO remove || true

          # put application back online
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan up}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def migrainestudynow_prod(options={})
        old_build = Version.get_build(migrainestudynow_prod_version)
        build = migrainestudynow_dev_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{ssh #{migrainestudynow_prod_user}@#{migrainestudynow_prod_ip} "cd #{site_path} && /usr/bin/php artisan down"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --delete-excluded #{site_path} #{migrainestudynow_prod_user}@#{migrainestudynow_prod_ip}:#{site_root}}

          # run database migrations
          run_cmd %Q{ssh #{migrainestudynow_prod_user}@#{migrainestudynow_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{migrainestudynow_prod_user}@#{migrainestudynow_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{migrainestudynow_prod_user}@#{migrainestudynow_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def migrainestudynow_environments
        [
          {
            :name => 'dev',
            :method => 'migrainestudynow_dev',
            :current_version => migrainestudynow_dev_version,
            :current_build => migrainestudynow_dev_build,
            :next_build => migrainestudynow_head_build
          },
          {
            :name => 'prod',
            :method => 'migrainestudynow_prod',
            :current_version => migrainestudynow_prod_version,
            :current_build => migrainestudynow_prod_build,
            :next_build => migrainestudynow_dev_build
          }        
        ]
      end
    end
  end
end
