require File.expand_path('../../helper', __FILE__)
require "stacks/cymbaltapregnancyregistry.rb"

module Deployinator
  module Stacks
    class Tester
      include Deployinator::Stacks::CymbaltaPregnancyRegistry
    end

    # I ran this with this command:
    # ruby -I test test/stacks/cymbaltapregnancyregistry_test.rb
    class CymbaltaPregnancyRegistryTest < Test::Unit::TestCase
      def setup
        @site_path = "/var/www/sites/cymbaltapregnancyregistry"
        @ssh_stage = %Q{ssh www-data@52.25.81.13 cd #{ @site_path } &&} 
        @ssh_prod = %Q{ssh www-data@54.201.142.33 cd #{ @site_path } &&} 
      end

      def test_artisan_down_stage
        t = Tester.new
        t.environment :stage
        expected = "#{ @ssh_stage } /usr/bin/php artisan down --env=stage || true"
        assert_equal expected, t.artisan_down
      end

      def test_artisan_down_prod
        t = Tester.new
        t.environment :prod
        expected = "#{ @ssh_prod } /usr/bin/php artisan down || true"
        assert_equal expected, t.artisan_down
      end

      def test_rsync_site_stage
        t = Tester.new
        t.environment :stage
        expected = %Q{rsync -ave ssh --delete --force --exclude='storage/*/*/**' --exclude='vendor/' --exclude='.git/' --exclude='.gitignore' --exclude='.env' --filter "protect .env" --filter "protect down" --filter "protect vendor/" --filter "protect storage/*/**" /tmp/cymbaltapregnancyregistry www-data@52.25.81.13:#{ @site_path }}
        assert_equal expected, t.rsync_site_stage
      end

      def test_rsync_site_prod
        t = Tester.new
        t.environment :prod
        expected = %Q{#{ @ssh_prod } rsync -ave ssh --delete --force --delete-excluded #{ @site_path } --filter 'protect .env.php' --filter 'protect down' #{ @site_path } www-data@54.201.142.33:#{ @site_path }}
        assert_equal expected, t.rsync_site_prod
      end

      def test_composer_install_stage
        t = Tester.new
        t.environment :stage
        cmd = "/usr/local/bin/composer"
        opt = "install --no-dev"
        expected = "#{ @ssh_stage } #{ cmd } #{ opt }"
        assert_equal expected, t.composer_install
      end

      def test_composer_install_prod
        t = Tester.new
        t.environment :prod
        cmd = "/usr/local/bin/composer"
        opt = "dump-autoload -o"
        expected = "#{ @ssh_prod } #{ cmd } #{ opt }"
        assert_equal expected, t.composer_install
      end

      def test_artisan_migrate_stage
        t = Tester.new
        t.environment :stage
        cmd = "/usr/bin/php artisan migrate"
        opt = "--seed --env=stage"
        expected = "#{ @ssh_stage } #{ cmd } #{ opt }"
        assert_equal expected, t.artisan_migrate
      end

      def test_artisan_migrate_prod
        t = Tester.new
        t.environment :prod
        cmd = "/usr/bin/php artisan migrate"
        opt = "--force"
        expected = "#{ @ssh_prod } #{ cmd } #{ opt }"
        assert_equal expected, t.artisan_migrate
      end

      def test_artisan_up_stage
        t = Tester.new
        t.environment :stage
        cmd = "/usr/bin/php artisan up"
        opt = "--env=stage"
        expected = "#{ @ssh_stage } #{ cmd } #{ opt }"
        assert_equal expected, t.artisan_up
      end

      def test_artisan_up_prod
        t = Tester.new
        t.environment :prod
        cmd = "/usr/bin/php artisan up"
        opt = ""
        expected = "#{ @ssh_prod } #{ cmd } #{ opt }"
        assert_equal expected, t.artisan_up
      end

      def test_environment
        t = Tester.new
        assert_equal :stage, t.environment( :stage )
        assert_equal :stage, t.environment
        assert_equal :prod, t.environment( :prod )
        assert_equal :prod, t.environment
      end

      def test_user
        t = Tester.new
        assert_equal "www-data", t.user
      end

      def test_ip
        t = Tester.new
        t.environment :stage
        assert_equal "52.25.81.13", t.ip
      end

      def test_ssh_cmd
        t = Tester.new
        t.environment :stage
        expected = %Q{#{ @ssh_stage } echo 'test'}
        assert_equal expected, t.ssh_cmd( "echo 'test'" )
      end

      def test_stage_version
        t = Tester.new
        t.environment :stage
        expected = "cat /tmp/cymbaltapregnancyregistry/version.txt" 
        assert_equal expected, t.stage_version_string
      end

      def test_prod_version
        t = Tester.new
        t.environment :prod
        expected = %Q{#{ @ssh_prod } cat version.txt}
        assert_equal expected, t.prod_version_string
      end
    end
  end
end
