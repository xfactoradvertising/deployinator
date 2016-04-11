module Deployinator
  module Stacks
    module Aahstudy
      def aahstudy_git_repo_url
        "git@github.com:xfactoradvertising/aahstudy.git"
      end

      def aahstudy_user
        'www-data'
      end

      def aahstudy_stage_ip
        '52.25.81.13'
      end

      def aahstudy_prod_ip
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

      def aahstudy_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def aahstudy_stage_version
        %x{ssh #{aahstudy_user}@#{aahstudy_stage_ip} 'cat #{site_path}/version.txt'}
      end

      def aahstudy_stage_build
        Version.get_build(aahstudy_stage_version)
      end

      def aahstudy_prod_version
        %x{ssh #{aahstudy_user}@#{aahstudy_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def aahstudy_prod_build
        Version.get_build(aahstudy_prod_version)
      end

      def aahstudy_head_build
        %x{git ls-remote #{aahstudy_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def aahstudy_stage(options={})
        old_build = aahstudy_stage_build

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = aahstudy_head_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{aahstudy_user}@#{aahstudy_stage_ip} "cd #{site_path} && /usr/bin/php artisan down --env=stage || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' --exclude='.env' --filter "protect .env" --filter "protect down" --filter "protect vendor/" --filter "protect storage/*/**" #{aahstudy_git_checkout_path}/ #{aahstudy_user}@#{aahstudy_stage_ip}:#{site_path}}

          # install dependencies
          run_cmd %Q{ssh #{aahstudy_user}@#{aahstudy_stage_ip} "cd #{site_path} && /usr/local/bin/composer install --no-dev"}

          # run db migrations
          run_cmd %Q{ssh #{aahstudy_user}@#{aahstudy_stage_ip} "cd #{site_path} && /usr/bin/php artisan migrate --seed --env=stage"}

          # put application back online
          run_cmd %Q{ssh #{aahstudy_user}@#{aahstudy_stage_ip} "cd #{site_path} && /usr/bin/php artisan up --env=stage"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'STAGE', :send_email => false) # TODO make email true

      end

      def aahstudy_prod(options={})
        old_build = aahstudy_prod_build
        build = aahstudy_stage_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{aahstudy_user}@#{aahstudy_prod_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          run_cmd %Q{ssh #{aahstudy_user}@#{aahstudy_stage_ip} "rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='storage/*/**' --exclude='.env' --filter 'protect .env' --filter 'protect down' --filter 'protect storage/*/**' #{site_path}/ #{aahstudy_user}@#{aahstudy_prod_ip}:#{site_path}"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{aahstudy_user}@#{aahstudy_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # run database migrations
          run_cmd %Q{ssh #{aahstudy_user}@#{aahstudy_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force --seed"}

          # take application online
          run_cmd %Q{ssh #{aahstudy_user}@#{aahstudy_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def aahstudy_environments
        [
          {
            :name => 'stage',
            :method => 'aahstudy_stage',
            :current_version => aahstudy_stage_version,
            :current_build => aahstudy_stage_build,
            :next_build => aahstudy_head_build
          },
          {
            :name => 'prod',
            :method => 'aahstudy_prod',
            :current_version => aahstudy_prod_version,
            :current_build => aahstudy_prod_build,
            :next_build => aahstudy_stage_build
          }        
        ]
      end
    end
  end
end
