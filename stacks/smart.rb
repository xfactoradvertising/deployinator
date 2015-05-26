module Deployinator
  module Stacks
    module Smart
      def smart_git_repo_url
        "git@github.com:xfactoradvertising/smart.git"
      end

      def smart_user
        'www-data'
      end

      def smart_stage_ip
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

      def smart_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def smart_dev_version
        %x{cat #{smart_git_checkout_path}/version.txt}
      end

      def smart_dev_build
        Version.get_build(smart_dev_version)
      end

      def smart_stage_version
        %x{ssh #{smart_user}@#{smart_stage_ip} 'cat #{site_path}/version.txt'}
      end

      def smart_stage_build
        Version.get_build(smart_stage_version)
      end

      def smart_head_build
        %x{git ls-remote #{smart_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def smart_dev(options={})
        old_build = Version.get_build(smart_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = smart_head_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan down || true} # return true so command is non-fatal

          # sync site files to final destination
          run_cmd %Q{rsync -av --delete --force --exclude='app/storage/' --exclude='public/assets/audio/' --exclude='public/assets/files/' --exclude='app/files/*' --exclude='/vendor/' --exclude='.git/' --exclude='.gitignore' #{smart_git_checkout_path}/ #{site_path}}

          # additionally sync top-level storage dirs (but not their contents)
          run_cmd %Q{rsync -lptgoDv --dirs --delete --force --exclude='.gitignore' #{smart_git_checkout_path}/app/storage/ #{site_path}/app/storage}

          # ensure storage is writable (shouldn't have to do this but running webserver as different user)
          run_cmd %Q{chmod 777 #{site_path}/app/storage/*}

          # smart-specific chmods
          run_cmd %Q{chmod 777 #{site_path}/app/storage/}
          run_cmd %Q{chmod 777 #{site_path}/public/assets/audio}
          run_cmd %Q{chmod 777 #{site_path}/public/assets/files}
          run_cmd %Q{chmod 777 #{site_path}/app/files}

          # install dependencies (vendor dir was probably completely removed via above)
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

      def smart_stage(options={})
        old_build = Version.get_build(smart_prod_version)
        build = smart_dev_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{smart_user}@#{smart_stage_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='public/assets/audio/' --exclude='public/assets/files/' --exclude='app/files/*' #{site_path} --filter "protect .env.php" --filter "protect down" #{smart_user}@#{smart_stage_ip}:#{site_root}}

          # run database migrations
          run_cmd %Q{ssh #{smart_user}@#{smart_stage_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force --env=production"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{smart_user}@#{smart_stage_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{smart_user}@#{smart_stage_ip} "cd #{site_path} && /usr/bin/php artisan up --env=production"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'STAGE', :send_email => false) # TODO make email true
      end

      def smart_environments
        [
          {
            :name => 'dev',
            :method => 'smart_dev',
            :current_version => smart_dev_version,
            :current_build => smart_dev_build,
            :next_build => smart_head_build
          },
          {
            :name => 'prod',
            :method => 'smart_prod',
            :current_version => smart_prod_version,
            :current_build => smart_prod_build,
            :next_build => smart_dev_build
          }        
        ]
      end
    end
  end
end
