module Deployinator
  module Stacks
    module Blueprint2
      def blueprint2_git_repo_url
        "git@github.com:xfactoradvertising/blueprint.git"
      end

      def blueprint2_user
        'www-data'
      end

      def blueprint2_stage_ip
        '52.25.81.13'
      end

      def blueprint2_prod_ip
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

      def blueprint2_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def blueprint2_stage_version
        %x{ssh #{blueprint2_user}@#{blueprint2_stage_ip} 'cat #{site_path}/version.txt'}
      end

      def blueprint2_stage_build
        Version.get_build(blueprint2_stage_version)
      end

      def blueprint2_prod_version
        %x{ssh #{blueprint2_user}@#{blueprint2_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def blueprint2_prod_build
        Version.get_build(blueprint2_prod_version)
      end

      def blueprint2_head_build
        # NOTE explicitly getting branch HEAD revision here (could move to a helper)
        # %x{git ls-remote #{blueprint2_git_repo_url} HEAD | cut -c1-7}.chomp
        %x{git ls-remote #{blueprint2_git_repo_url} blueprint2 HEAD | tail -1 | cut -c1-7}.chomp
      end

      def blueprint2_stage(options={})
        old_build = blueprint2_stage_build

        #git_cmd = old_build ? :git_freshen_clone : :github_clone
        git_cmd = old_build ? :git_freshen_clone_branch : :github_clone_branch
        #send(git_cmd, stack, 'sh -c')
        send(git_cmd, stack, 'blueprint2', 'sh -c')

        git_bump_version stack, ''

        build = blueprint2_head_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{blueprint2_user}@#{blueprint2_stage_ip} "cd #{site_path} && /usr/bin/php artisan down --env=stage || true"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' --exclude='.env' --filter "protect .env" --filter "protect down" --filter "protect vendor/" --filter "protect storage/*/**" #{blueprint2_git_checkout_path}/ #{blueprint2_user}@#{blueprint2_stage_ip}:#{site_path}}

          # install dependencies
          run_cmd %Q{ssh #{blueprint2_user}@#{blueprint2_stage_ip} "cd #{site_path} && /usr/local/bin/composer install --no-dev"}

          # run db migrations
          run_cmd %Q{ssh #{blueprint2_user}@#{blueprint2_stage_ip} "cd #{site_path} && /usr/bin/php artisan migrate:refresh --seed --env=stage"}

          # put application back online
          run_cmd %Q{ssh #{blueprint2_user}@#{blueprint2_stage_ip} "cd #{site_path} && /usr/bin/php artisan up --env=stage"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'STAGE', :send_email => false) # TODO make email true

      end

      def blueprint2_prod(options={})
        old_build = blueprint2_prod_build
        build = blueprint2_stage_build

        begin
          # take application offline (maintenance mode)
          # return true so command is non-fatal (artisan doesn't exist the first time)
          run_cmd %Q{ssh #{blueprint2_user}@#{blueprint2_prod_ip} "cd #{site_path} && /usr/bin/php artisan down || true"}

          # sync new app contents
          run_cmd %Q{ssh #{blueprint2_user}@#{blueprint2_stage_ip} "rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='storage/*/**' --exclude='.env' --filter 'protect .env' --filter 'protect down' --filter 'protect storage/*/**' #{site_path}/ #{blueprint2_user}@#{blueprint2_prod_ip}:#{site_path}"}

          # run database migrations
          run_cmd %Q{ssh #{blueprint2_user}@#{blueprint2_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --seed"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{blueprint2_user}@#{blueprint2_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{blueprint2_user}@#{blueprint2_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def blueprint2_environments
        [
          {
            :name => 'stage',
            :method => 'blueprint2_stage',
            :current_version => blueprint2_stage_version,
            :current_build => blueprint2_stage_build,
            :next_build => blueprint2_head_build
          },
          {
            :name => 'prod',
            :method => 'blueprint2_prod',
            :current_version => blueprint2_prod_version,
            :current_build => blueprint2_prod_build,
            :next_build => blueprint2_stage_build
          }        
        ]
      end
    end
  end
end
