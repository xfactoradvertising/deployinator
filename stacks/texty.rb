module Deployinator
  module Stacks
    module Texty
      def texty_git_repo_url
        "git@github.com:xfactoradvertising/texty.git"
      end

      def texty_user
        'www-data'
      end

      def texty_stage_ip
        '52.25.81.13'
      end

      def texty_prod_ip
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

      def texty_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def texty_stage_version
        %x{ssh #{texty_user}@#{texty_stage_ip} 'cat #{site_path}/version.txt'}
      end

      def texty_stage_build
        Version.get_build(texty_stage_version)
      end

      def texty_prod_version
        %x{ssh #{texty_user}@#{texty_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def texty_prod_build
        Version.get_build(texty_prod_version)
      end

      def texty_head_build
        %x{git ls-remote #{texty_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def texty_stage(options={})
        old_build = texty_stage_build

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = texty_head_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{texty_user}@#{texty_stage_ip} "cd #{site_path} && /usr/bin/php artisan down --env=stage || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' --exclude='.env' --filter "protect .env" --filter "protect down" --filter "protect vendor/" --filter "protect storage/*/**" #{texty_git_checkout_path}/ #{texty_user}@#{texty_stage_ip}:#{site_path}}

          # install dependencies
          run_cmd %Q{ssh #{texty_user}@#{texty_stage_ip} "cd #{site_path} && /usr/local/bin/composer install --no-dev"}

          # run db migrations
          run_cmd %Q{ssh #{texty_user}@#{texty_stage_ip} "cd #{site_path} && /usr/bin/php artisan migrate --seed --env=stage"}

          # put application back online
          run_cmd %Q{ssh #{texty_user}@#{texty_stage_ip} "cd #{site_path} && /usr/bin/php artisan up --env=stage"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'STAGE', :send_email => false) # TODO make email true

      end

      def texty_prod(options={})
        old_build = texty_prod_build
        build = texty_stage_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{texty_user}@#{texty_prod_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          run_cmd %Q{ssh #{texty_user}@#{texty_stage_ip} "rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='storage/*/**' --exclude='.env' --filter 'protect .env' --filter 'protect down' --filter 'protect storage/*/**' #{site_path}/ #{texty_user}@#{texty_prod_ip}:#{site_path}"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{texty_user}@#{texty_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # run database migrations
          run_cmd %Q{ssh #{texty_user}@#{texty_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force --seed"}

          # take application online
          run_cmd %Q{ssh #{texty_user}@#{texty_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def texty_environments
        [
          {
            :name => 'stage',
            :method => 'texty_stage',
            :current_version => texty_stage_version,
            :current_build => texty_stage_build,
            :next_build => texty_head_build
          },
          {
            :name => 'prod',
            :method => 'texty_prod',
            :current_version => texty_prod_version,
            :current_build => texty_prod_build,
            :next_build => texty_stage_build
          }        
        ]
      end
    end
  end
end
