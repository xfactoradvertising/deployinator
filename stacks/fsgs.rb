module Deployinator
  module Stacks
    module Fsgs
      def fsgs_git_repo_url
        "git@github.com:xfactoradvertising/com.fsgsresearch.git"
      end

      def prod_user
        'ubuntu'
      end

      def prod_ip
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

      def fsgs_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def fsgs_dev_version
        %x{cat #{fsgs_git_checkout_path}/version.txt}
      end

      def fsgs_dev_build
        Version.get_build(fsgs_dev_version)
      end

      def fsgs_prod_version
        %x{ssh #{prod_user}@#{prod_ip} 'cat #{site_path}/version.txt'}
      end

      def fsgs_prod_build
        Version.get_build(fsgs_prod_version)
      end

      def fsgs_head_build
        %x{git ls-remote #{fsgs_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def fsgs_dev(options={})
        old_build = Version.get_build(fsgs_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = fsgs_head_build

        begin
          # sync files to final destination
          run_cmd %Q{rsync -av --delete --force --exclude='.git/' --exclude='.gitignore' #{fsgs_git_checkout_path}/ #{site_path}}
          # set permissions so webserver can write TODO setup passwordless sudo to chown&chmod instead? or
            # maybe set CAP_CHOWN for deployinator?
          # run_cmd %Q{chmod 777 #{site_path}/files}
          # run_cmd %Q{chmod 777 #{site_path}/app/storage/*}
          # run_cmd %Q{cd #{site_path} && /usr/local/bin/composer install}
          # run_cmd %Q{cd #{site_path} && /usr/local/bin/composer dump-autoload}
          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def fsgs_prod(options={})
        old_build = Version.get_build(fsgs_prod_version)
        build = fsgs_dev_build

        begin
          run_cmd %Q{rsync -ave ssh --delete --force #{site_path} #{prod_user}@#{prod_ip}:#{site_root}}
          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def fsgs_environments
        [
          {
            :name => 'dev',
            :method => 'fsgs_dev',
            :current_version => fsgs_dev_version,
            :current_build => fsgs_dev_build,
            :next_build => fsgs_head_build
          },
          {
            :name => 'prod',
            :method => 'fsgs_prod',
            :current_version => fsgs_prod_version,
            :current_build => fsgs_prod_build,
            :next_build => fsgs_dev_build
          }         
        ]
      end
    end
  end
end