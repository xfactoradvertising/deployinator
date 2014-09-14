module Deployinator
  module Stacks
    module Combatreport
      def prod_user
        'www-data'
      end

      def prod_ip
        '10.248.3.116' #web1
      end

      def prod_version
        # just use the date stamp of the last deploy as the current production version
        version = %x{grep 'combat_report' #{__FILE__}../log/deployinator.log | tail -1 | cut -d'|' -f1}
        version.empty? ? 'none' : version
      end

      # run unite to backup dev and push to prod
      def combatreport_prod(options={})
        begin
          # TODO backup current production site first and try to restore that in case of disaster
          run_cmd %Q{ssh #{prod_user}@#{prod_ip} "cd /opt/unite;/usr/bin/php5 unite.php"}
          log_and_stream "Done!<br>"
        rescue
          log_and_stream "Failed!<br>"
        end

        log_and_shout(:old_build => 'dev_current', :build => 'prod_current', :env => 'PROD', :send_email => false)
      end

      def combatreport_environments
        [
          # "push to dev" is just changing http://combatreport.xfactordevelopment.com/ directly
          {
            :name => 'prod',
            :method => 'combatreport_prod',
            :current_version => prod_version,
            # TODO get last-modified date of dev site and show that
            # (e.g. use https://github.com/pe7er/db8sitelastmodified/blob/master/helper.php or similar)
            :current_build => 'dev',
            :next_build => 'prod'
          }         
        ]
      end
    end
  end
end