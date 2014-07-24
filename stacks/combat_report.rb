module Deployinator
  module Stacks
    module CombatReport
      def combat_report_git_repo_url
        "git@github.com:xfactoradvertising/combat-report.git"
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

      def combat_report_git_checkout_path
        "#{checkout_root}/#{stack}"
      end

      def combat_report_dev_version
        %x{cat #{combat_report_git_checkout_path}/version.txt}
      end

      def combat_report_dev_build
        Version.get_build(combat_report_dev_version)
      end

      def combat_report_prod_version
        %x{ssh #{prod_user}@#{prod_ip} 'cat #{site_path}/version.txt'}
      end

      def combat_report_prod_build
        Version.get_build(combat_report_prod_version)
      end

      def combat_report_head_build
        %x{git ls-remote #{combat_report_git_repo_url} HEAD | cut -c1-7}.chomp
      end

      def combat_report_dev(options={})
        old_build = Version.get_build(combat_report_dev_version)

        git_cmd = old_build ? :git_freshen_clone : :github_clone
        send(git_cmd, stack, 'sh -c')

        git_bump_version stack, ''

        build = combat_report_head_build

        begin
          # sync files to final destination
          run_cmd %Q{rsync -av --delete --force --exclude='.git/' --exclude='.gitignore' #{combat_report_git_checkout_path}/ #{site_path}}
          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :send_email => false) # TODO make email true

      end

      def combat_report_prod(options={})
        old_build = Version.get_build(combat_report_prod_version)
        build = combat_report_dev_build

        begin
          run_cmd %Q{rsync -ave ssh --delete --force #{site_path} #{prod_user}@#{prod_ip}:#{site_root}}
          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => old_build, :build => build, :env => 'PROD', :send_email => false) # TODO make email true
      end

      def combat_report_environments
        [
          {
            :name => 'dev',
            :method => 'combat_report_dev',
            :current_version => combat_report_dev_version,
            :current_build => combat_report_dev_build,
            :next_build => combat_report_head_build
          },
          {
            :name => 'prod',
            :method => 'combat_report_prod',
            :current_version => combat_report_prod_version,
            :current_build => combat_report_prod_build,
            :next_build => combat_report_dev_build
          }         
        ]
      end
    end
  end
end