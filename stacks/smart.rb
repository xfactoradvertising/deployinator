module Deployinator
  module Stacks
    module Smart
      def smart_git_repo_url
        "git@github.com:xfactoradvertising/smart.git"
      end

      def smart_prod_user
        'www-data'
      end

      def smart_prod_ip
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

      def smart_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def smart_staging_version
        %x{cat #{smart_git_checkout_path}/version.txt}
      end

      def smart_staging_build
        Version.get_build(smart_staging_version)
      end

      def smart_prod_version
        %x{ssh #{smart_prod_user}@#{smart_prod_ip} 'cat #{site_path}/version.txt'}
      end

      def smart_prod_build
        Version.get_build(smart_prod_version)
      end

      def smart_head_build
        %x{git ls-remote #{smart_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def smart_staging(options={})
        old_build = Version.get_build(smart_staging_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = smart_head_build

        begin
          # TODO check for zip files in app/views or app/controllers (or app/* ?) and fail..these break composer dump-autoload

          # take site offline for deployment
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan down || true} # return true so command is non-fatal

          # sync files to final destination
          run_cmd %Q{rsync -av --delete --force --exclude='app/storage/' --exclude='public/assets/audio/' --exclude='public/assets/files/' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' #{smart_git_checkout_path}/ #{site_path}}

          # set permissions so webserver can write TODO setup passwordless sudo to chown&chmod instead? or
            # maybe set CAP_CHOWN for deployinator?
          run_cmd %Q{chmod 777 #{site_path}/app/storage/*}
          run_cmd %Q{chmod 777 #{site_path}/public/assets/audio}
          run_cmd %Q{chmod 777 #{site_path}/public/assets/files}

          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install  --no-dev}

          #probably don't need this..use post-install-cmd to clear and optimize instead
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer dump-autoload}

          # take site back online
          run_cmd %Q{cd #{site_path} && /usr/bin/php artisan up}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def smart_prod(options={})
        old_build = Version.get_build(smart_prod_version)
        build = smart_staging_build

        begin
          # take application offline (maintenance mode)
          run_cmd %Q{ssh #{smart_prod_user}@#{smart_prod_ip} "cd #{site_path} && /usr/bin/php artisan down || true"} # return true so command is non-fatal (artisan doesn't exist the first time)

          # TODO figure out how to keep from deleting smart/app/storage/meta/down (which enables the site)

          # sync new app contents
          run_cmd %Q{rsync -ave ssh --delete --force --exclude='public/assets/audio/' --exclude='public/assets/files/' #{site_path} #{smart_prod_user}@#{smart_prod_ip}:#{site_root}}

          # generate optimized autoload files
          run_cmd %Q{ssh #{smart_prod_user}@#{smart_prod_ip} "cd #{site_path} && /usr/local/bin/composer dump-autoload -o"}

          # take application online
          run_cmd %Q{ssh #{smart_prod_user}@#{smart_prod_ip} "cd #{site_path} && /usr/bin/php artisan up"}

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def smart_environments
        [
          {
            :name => 'staging',
            :method => 'smart_staging',
            :current_version => smart_staging_version,
            :current_build => smart_staging_build,
            :next_build => smart_head_build
          },
          {
            :name => 'prod',
            :method => 'smart_prod',
            :current_version => smart_prod_version,
            :current_build => smart_prod_build,
            :next_build => smart_staging_build
          }        
        ]
      end
    end
  end
end