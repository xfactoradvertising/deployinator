module Deployinator
  module Stacks
    module CymbaltaPregnancyRegistry
      # Helper methods
      def artisan_down
        opt = environment == :stage ? "--env=stage " : ""
        ssh_cmd "/usr/bin/php artisan down #{ opt }|| true"
      end

      def rsync_site_stage
        rsync = %Q{rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' --exclude='.env' --filter "protect .env" --filter "protect down" --filter "protect vendor/" --filter "protect storage/*/**"}

        source = checkout_path
        destination = %Q{#{ user }@#{ ip }:#{ site_path }}

        %Q{#{ rsync } #{ source } #{ destination }} 
      end

      def rsync_site_prod
        rsync = %Q{rsync -ave ssh --delete --force --delete-excluded #{site_path} --filter 'protect .env.php' --filter 'protect down'}

        source = site_path
        destination = %Q{#{ user }@#{ ip }:#{ site_path }}

        ssh_cmd %Q{#{ rsync } #{ source } #{ destination }}
      end

      def composer_install
        opt = environment == :stage ? 
          "install --no-dev" : "dump-autoload -o"
        ssh_cmd "/usr/local/bin/composer #{ opt }"
      end

      def artisan_migrate
        opt = environment == :stage ? "--seed --env=stage" : "--force"
        ssh_cmd "/usr/bin/php artisan migrate #{ opt }"
      end

      def artisan_up
        opt = environment == :stage ? "--env=stage" : ""
        ssh_cmd "/usr/bin/php artisan up #{ opt }"
      end

      # Utility methods
      def ssh_cmd command
        %Q{ssh #{ user }@#{ ip } cd #{ site_path } && #{ command }}
      end

      def environment env = nil
        @environment = env if env
        @environment 
      end

      def user
        "www-data"
      end

      def ip
        case environment
        when :stage
          '52.25.81.13'
        when :prod
          '54.201.142.33'
        else
          raise "Invalid environment"
        end
      end

      def site_path
        '/var/www/sites/cymbaltapregnancyregistry'
      end

      def checkout_path
        '/tmp/cymbaltapregnancyregistry'
      end

      def deploy
        begin
          # Putting run_cmd here makes it easy to test
          # each function.
          rsync_site = environment == :stage ? 
            rsync_site_stage : rsync_site_prod

          run_cmd artisan_down
          run_cmd rsync_site
          run_cmd composer_install
          run_cmd artisan_migrate
          run_cmd artisan_up

          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end
      end
      
      # Staging methods
      def stage_version_string
        "cat #{ checkout_path }/version.txt"
      end

      def stage_version
        @stage_version ||= %x{stage_version}
      end

      def head_build
        @head_build ||=
          %x{git ls-remote #{ checkout_path } HEAD | cut -c1-7}.chomp
      end

      def cymbaltapregnancyregistry_stage
        environment :stage
        old_build = Version.get_build stage_version

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')
        git_bump_version stack, ''

        build = head_build

        deploy

        log_and_shout old_build: old_build, build: build, 
          send_email: false
      end

      # Production methods
      def prod_version_string
        ssh_cmd "cat version.txt"
      end

      def prod_version
        @prod_version ||= %x{prod_version_string}
      end

      def cymbaltapregnancyregistry_prod
        environment :prod
        old_build = Version.get_build prod_version

        build = prod_build

        deploy

        log_and_shout old_build: old_build, build: build, 
          env: 'PROD', send_email: false
      end

      # Standard Deployinator interface
      def cymbaltapregnancyregistry_environments
        [
          {
            :name => 'stage',
            :method => 'cymbaltapregnancyregistry_stage',
            :current_version => stage_version,
            :current_build => Version.get_build( stage_version ),
            :next_build => head_build
          },
          {
            :name => 'prod',
            :method => 'cymbaltapregnancyregistry_prod',
            :current_version => prod_version,
            :current_build => Version.get_build( prod_version ),
            :next_build => Version.get_build( stage_version )
          }
        ]
      end
    end
  end
end
