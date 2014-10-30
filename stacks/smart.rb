module Deployinator
  module Stacks
    module Smart
      def smart_git_repo_url
        "git@github.com:xfactoradvertising/smart.git"
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

      # def smart_prod_version
      #   %x{ssh 54.245.225.193 "cat #{smart_git_checkout_path}/version.txt"}
      # end

      def smart_dev_build
        Version.get_build(smart_dev_version)
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
          # TODO check for zip files in app/views or app/controllers (or app/* ?) and fail..these break composer dump-autoload
          # sync files to final destination
          run_cmd %Q{rsync -av --delete --force --delete-excluded --exclude='.git/' --exclude='.gitignore' #{smart_git_checkout_path}/ #{site_path}}
          # set permissions so webserver can write TODO setup passwordless sudo to chown&chmod instead? or
            # maybe set CAP_CHOWN for deployinator?
          run_cmd %Q{chmod 777 #{site_path}/files}
          run_cmd %Q{chmod 777 #{site_path}/app/storage/*}
          run_cmd %Q{chmod 777 #{site_path}/public/assets/audio}
          run_cmd %Q{chmod 777 #{site_path}/public/assets/files}
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install}
          run_cmd %Q{cd #{site_path} && /usr/local/bin/composer dump-autoload}
          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def smart_environments
        [
          {
            :name => 'dev',
            :method => 'smart_dev',
            :current_version => smart_dev_version,
            :current_build => smart_dev_build,
            :next_build => smart_head_build
          }#,
          # {
          #   :name => 'prod',
          #   :method => 'smart_prod',
          #   :current_version => smart_prod_version,
          #   :current_build => smart_prod_build,
          #   :next_build => smart_dev_build
          # }          
        ]
      end
    end
  end
end