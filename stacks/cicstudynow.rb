module Deployinator
  module Stacks
    module Cicstudynow
      def cicstudynow_git_repo_url
        "git@github.com:xfactoradvertising/com.cicstudynow.git"
      end

      def cicstudynow_prod_user
        'ubuntu'
      end

      def cicstudynow_prod_ip
        '10.248.3.116'
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

      def cicstudynow_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def cicstudynow_dev_version
        %x{cat #{cicstudynow_git_checkout_path}/version.txt}
      end

      def cicstudynow_dev_build
        Version.get_build(cicstudynow_dev_version)
      end

      def cicstudynow_prod_version
        %x{ssh #{cicstudynow_prod_user}@#{cicstudynow_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def cicstudynow_prod_build
        Version.get_build(cicstudynow_prod_version)
      end

      def cicstudynow_head_build
        %x{git ls-remote #{cicstudynow_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def cicstudynow_dev(options={})
        old_build = Version.get_build(cicstudynow_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = cicstudynow_head_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan down || true} # return true so command is non-fatal

          # sync files to final destination
          run_cmd %Q{rsync -av --delete --force --include='app/storage/meta'  --exclude='app/storage/*' --exclude='vendor/*' --exclude='.git/' --exclude='.gitignore' #{cicstudynow_git_checkout_path}/ #{site_path}}

          # ensure storage is writable (shouldn't have to do this but running webserver as different user)
          run_cmd %Q{chmod -R 777 #{site_path}/app/storage}

          # install dependencies (vendor dir was probably completely removed via above)
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install --no-dev}

          # run db migrations
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan migrate}

          # put application back online
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan up}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def cicstudynow_prod(options={})
        old_build = Version.get_build(cicstudynow_prod_version)
        build = cicstudynow_dev_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{ssh #{cicstudynow_prod_user}@#{cicstudynow_prod_ip} "cd #{site_path} && /usr/bin/php artisan down"}

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --delete-excluded #{site_path} #{cicstudynow_prod_user}@#{cicstudynow_prod_ip}:#{site_root}}

          # run database migrations
          run_cmd %Q{ssh #{cicstudynow_prod_user}@#{cicstudynow_prod_ip} "cd #{site_path} && /usr/bin/php artisan migrate --force"}

          # generate optimized autoload files
          run_cmd %Q{ssh #{cicstudynow_prod_user}@#{cicstudynow_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{cicstudynow_prod_user}@#{cicstudynow_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def cicstudynow_environments
        [
          {
            :name => 'dev',
            :method => 'cicstudynow_dev',
            :current_version => cicstudynow_dev_version,
            :current_build => cicstudynow_dev_build,
            :next_build => cicstudynow_head_build
          },
          {
            :name => 'prod',
            :method => 'cicstudynow_prod',
            :current_version => cicstudynow_prod_version,
            :current_build => cicstudynow_prod_build,
            :next_build => cicstudynow_dev_build
          }        
        ]
      end    end
  end
end
