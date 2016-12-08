module Deployinator
  module Stacks
    module Cymbaltapregnancyregistry
      def cymbaltapregnancyregistry_git_repo_url
        "git@github.com:xfactoradvertising/cymbaltapregnancyregistry.git"
      end

      def cymbaltapregnancyregistry_user
        'www-data'
      end

      def cymbaltapregnancyregistry_stage_ip
        '52.25.81.13'
      end

      def cymbaltapregnancyregistry_prod_ip
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

      def prod_path
        "#{site_root}/#{lillypregnancyregistry}"
      end

      def cymbaltapregnancyregistry_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def cymbaltapregnancyregistry_stage_version
        %x{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_stage_ip} 'cat #{site_path}/version.txt'}
      end

      def cymbaltapregnancyregistry_stage_build
        Version.get_build(cymbaltapregnancyregistry_stage_version)
      end

      def cymbaltapregnancyregistry_prod_version
        %x{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_prod_ip} 'cat #{prod_path}/version.txt'}
      end

      def cymbaltapregnancyregistry_prod_build
        Version.get_build(cymbaltapregnancyregistry_prod_version)
      end

      def cymbaltapregnancyregistry_head_build
        %x{git ls-remote #{cymbaltapregnancyregistry_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def cymbaltapregnancyregistry_stage(options={})
        old_build = cymbaltapregnancyregistry_stage_build

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = cymbaltapregnancyregistry_head_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_stage_ip} "cd #{site_path} && /usr/bin/php artisan down --env=stage || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' --exclude='.env' --filter "protect .env" --filter "protect down" --filter "protect vendor/" --filter "protect storage/*/**" #{cymbaltapregnancyregistry_git_checkout_path}/ #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_stage_ip}:#{site_path}}

          # install dependencies
          run_cmd %Q{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_stage_ip} "cd #{site_path} && /usr/local/bin/composer install --no-dev"}

          # run db migrations
          run_cmd %Q{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_stage_ip} "cd #{site_path} && /usr/bin/php artisan migrate --seed --env=stage"}

          # put application back online
          run_cmd %Q{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_stage_ip} "cd #{site_path} && /usr/bin/php artisan up --env=stage"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'STAGE', :send_email => false) # TODO make email true

      end

      def cymbaltapregnancyregistry_prod(options={})
        old_build = cymbaltapregnancyregistry_prod_build
        build = cymbaltapregnancyregistry_stage_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_prod_ip} "cd #{prod_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          run_cmd %Q{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_stage_ip} "rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='storage/*/**' --exclude='.env' --filter 'protect .env' --filter 'protect down' --filter 'protect storage/*/**' #{site_path}/ #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_prod_ip}:#{prod_path}"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_prod_ip} "cd #{prod_path} && /usr/local/bin/composer dump-autoload -o"}

          # run database migrations
          run_cmd %Q{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_prod_ip} "cd #{prod_path} && /usr/bin/php artisan migrate --force --seed"}

          # take application online
          run_cmd %Q{ssh #{cymbaltapregnancyregistry_user}@#{cymbaltapregnancyregistry_prod_ip} "cd #{prod_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def cymbaltapregnancyregistry_environments
        [
          {
            :name => 'stage',
            :method => 'cymbaltapregnancyregistry_stage',
            :current_version => cymbaltapregnancyregistry_stage_version,
            :current_build => cymbaltapregnancyregistry_stage_build,
            :next_build => cymbaltapregnancyregistry_head_build
          },
          {
            :name => 'prod',
            :method => 'cymbaltapregnancyregistry_prod',
            :current_version => cymbaltapregnancyregistry_prod_version,
            :current_build => cymbaltapregnancyregistry_prod_build,
            :next_build => cymbaltapregnancyregistry_stage_build
          }        
        ]
      end
    end
  end
end
