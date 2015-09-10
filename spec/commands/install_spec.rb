require "spec_helper"

describe "bundle install with gem sources" do
  describe "the simple case" do
    it "prints output and returns if no dependencies are specified" do
      gemfile <<-G
        source "file://#{gem_repo1}"
      G

      bundle :install
      expect(out).to match(/no dependencies/)
    end

    it "does not make a lockfile if the install fails" do
      install_gemfile <<-G, :expect_err => true
        raise StandardError, "FAIL"
      G

      expect(err).to match(/StandardError, "FAIL"/)
      expect(bundled_app("gems.locked")).not_to exist
    end

    it "creates a gems.locked" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      expect(bundled_app("gems.locked")).to exist
    end

    it "creates lock files based on the gems.rb name" do
      gemfile bundled_app("OmgFile"), <<-G
        source "file://#{gem_repo1}"
        gem "rack", "1.0"
      G

      bundle "install --gemfile OmgFile"

      expect(bundled_app("OmgFile.lock")).to exist
    end

    it "doesn't delete the lockfile if one already exists" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      lockfile = File.read(bundled_app("gems.locked"))

      install_gemfile <<-G, :expect_err => true
        raise StandardError, "FAIL"
      G

      expect(File.read(bundled_app("gems.locked"))).to eq(lockfile)
    end

    it "does not touch the lockfile if nothing changed" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      expect { run "1" }.not_to change { File.mtime(bundled_app("gems.locked")) }
    end

    it "fetches gems" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      expect(default_bundle_path("gems/rack-1.0.0")).to exist
      should_be_installed("rack 1.0.0")
    end

    it "fetches gems when multiple versions are specified" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem 'rack', "> 0.9", "< 1.0"
      G

      expect(default_bundle_path("gems/rack-0.9.1")).to exist
      should_be_installed("rack 0.9.1")
    end

    it "fetches gems when multiple versions are specified take 2" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem 'rack', "< 1.0", "> 0.9"
      G

      expect(default_bundle_path("gems/rack-0.9.1")).to exist
      should_be_installed("rack 0.9.1")
    end

    it "raises an appropriate error when gems are specified using symbols" do
      install_gemfile(<<-G)
        source "file://#{gem_repo1}"
        gem :rack
      G
      expect(exitstatus).to eq(4) if exitstatus
    end

    it "pulls in dependencies" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rails"
      G

      should_be_installed "actionpack 2.3.2", "rails 2.3.2"
    end

    it "does the right version" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "0.9.1"
      G

      should_be_installed "rack 0.9.1"
    end

    it "does not install the development dependency" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "with_development_dependency"
      G

      should_be_installed "with_development_dependency 1.0.0"
      should_not_be_installed "activesupport 2.3.5"
    end

    it "resolves correctly" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "activemerchant"
        gem "rails"
      G

      should_be_installed "activemerchant 1.0", "activesupport 2.3.2", "actionpack 2.3.2"
    end

    it "activates gem correctly according to the resolved gems" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "activesupport", "2.3.5"
      G

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "activemerchant"
        gem "rails"
      G

      should_be_installed "activemerchant 1.0", "activesupport 2.3.2", "actionpack 2.3.2"
    end

    it "does not reinstall any gem that is already available locally" do
      system_gems "activesupport-2.3.2"

      build_repo2 do
        build_gem "activesupport", "2.3.2" do |s|
          s.write "lib/activesupport.rb", "ACTIVESUPPORT = 'fail'"
        end
      end

      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "activerecord", "2.3.2"
      G

      should_be_installed "activesupport 2.3.2"
    end

    it "works when the gemfile specifies gems that only exist in the system" do
      build_gem "foo", :to_system => true
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "foo"
      G

      should_be_installed "rack 1.0.0", "foo 1.0.0"
    end

    it "prioritizes local gems over remote gems" do
      build_gem "rack", "1.0.0", :to_system => true do |s|
        s.add_dependency "activesupport", "2.3.5"
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      should_be_installed "rack 1.0.0", "activesupport 2.3.5"
    end

    describe "with a gem that installs multiple platforms" do
      it "installs gems for the local platform as first choice" do
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "platform_specific"
        G

        run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
        expect(out).to eq("1.0.0 #{Gem::Platform.local}")
      end

      it "falls back on plain ruby" do
        simulate_platform "foo-bar-baz"
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "platform_specific"
        G

        run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
        expect(out).to eq("1.0.0 RUBY")
      end

      it "installs gems for java" do
        simulate_platform "java"
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "platform_specific"
        G

        run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
        expect(out).to eq("1.0.0 JAVA")
      end

      it "installs gems for windows" do
        simulate_platform mswin

        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "platform_specific"
        G

        run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
        expect(out).to eq("1.0.0 MSWIN")
      end
    end

    describe "doing bundle install foo" do
      before do
        gemfile <<-G
          source "file://#{gem_repo1}"
          gem "rack"
        G
        bundle "config path vendor"
      end

      it "works" do
        bundle "install"
        should_be_installed "rack 1.0"
      end

      # NOTE: This interface (`install; config --delete path; install --system`)
      # is a bit clunky.
      # (Just using `install; install --system` produces an error.)
      it "allows running bundle install --system without deleting foo" do
        bundle "install"
        bundle "config --delete path"
        bundle "install --system"
        FileUtils.rm_rf(bundled_app("vendor"))
        should_be_installed "rack 1.0"
      end

      it "allows running bundle install --system after deleting foo" do
        bundle "install"
        FileUtils.rm_rf(bundled_app("vendor"))
        bundle "config --delete path"
        bundle "install --system"
        should_be_installed "rack 1.0"
      end
    end

    it "finds gems in multiple sources" do
      build_repo2
      update_repo2

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        source "file://#{gem_repo2}"

        gem "activesupport", "1.2.3"
        gem "rack", "1.2"
      G

      should_be_installed "rack 1.2", "activesupport 1.2.3"
    end

    it "gives a useful error if no sources are set" do
      install_gemfile <<-G
        gem "rack"
      G

      bundle :install, :expect_err => true
      expect(out).to include("Your gems.rb has no gem server sources")
    end

    it "creates a gems.locked on a blank gems.rb" do
      install_gemfile <<-G
      G

      expect(File.exist?(bundled_app("gems.locked"))).to eq(true)
    end

    it "gracefully handles error when rubygems server is unavailable" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        source "http://localhost:9384"

        gem 'foo'
      G

      bundle :install
      expect(err).to include("Could not fetch specs from http://localhost:9384/")
      expect(err).not_to include("file://")
    end

    it "doesn't blow up when the local .bundle/config is empty" do
      FileUtils.mkdir_p(bundled_app(".bundle"))
      FileUtils.touch(bundled_app(".bundle/config"))

      install_gemfile(<<-G)
        source "file://#{gem_repo1}"

        gem 'foo'
      G
      expect(exitstatus).to eq(0) if exitstatus
    end

    it "doesn't blow up when the global .bundle/config is empty" do
      FileUtils.mkdir_p("#{Bundler.rubygems.user_home}/.bundle")
      FileUtils.touch("#{Bundler.rubygems.user_home}/.bundle/config")

      install_gemfile(<<-G)
        source "file://#{gem_repo1}"

        gem 'foo'
      G
      expect(exitstatus).to eq(0) if exitstatus
    end
  end

  describe "when Bundler root contains regex chars" do
    before do
      root_dir = tmp("foo[]bar")

      FileUtils.mkdir_p(root_dir)
      in_app_root_custom(root_dir)
    end

    it "doesn't blow up" do
      build_lib "foo"
      gemfile = <<-G
        gem 'foo', :path => "#{lib_path("foo-1.0")}"
      G
      File.open("gems.rb", "w") do |file|
        file.puts gemfile
      end

      bundle :install

      expect(exitstatus).to eq(0) if exitstatus
    end
  end

  describe "when requesting a quiet install via --quiet" do
    it "should be quiet" do
      gemfile <<-G
        gem 'rack'
      G

      bundle :install, :quiet => true
      expect(err).to include("Could not find gem 'rack'")
      expect(out).to_not include("Your gems.rb has no gem server sources")
      expect(err).to_not include("Your gems.rb has no gem server sources")
    end
  end

  describe "when using the --cache flag" do
    it "prints an error and exits" do
      gemfile <<-G
        gem 'rack'
      G

      bundle "install --cache"

      expect(err).to include("Please use `bundle cache` instead")
    end
  end

  describe "when using the --path flag" do
    it "print an error and exit" do
      gemfile <<-G
        gem 'rack'
      G

      bundle "install --path vendor/bundle"

      expect(err).to include("Please use `bundle config path")
    end
  end

  describe "using the cross-application user cache" do
    let(:source) { "http://localgemserver.test" }

    it "caches gems into the global cache on download" do
      gemfile <<-G
        source "#{source}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint"
      should_be_installed "rack 1.0.0"
      expect(download_cache(source, "rack-1.0.0.gem")).to exist
    end

    it "uses globally cached gems if they exist" do
      gemfile <<-G
        source "#{source}"
        gem "rack"
      G

      download_cache(source).mkpath
      FileUtils.cp(gem_repo1("gems/rack-1.0.0.gem"), download_cache(source, "rack-1.0.0.gem"))
      bundle :install, :artifice => "endpoint_no_gem"
      expect(exitstatus).to eq(0) if exitstatus
      should_be_installed "rack 1.0.0"
    end

    it "allows the global cache path to be configured" do
      bundle "config path.download_cache #{home("machine_cache")}"

      gemfile <<-G
        source "#{source}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint"
      should_be_installed "rack 1.0.0"
      cached_rack = home("machine_cache", download_cache_source_dir(source), "rack-1.0.0.gem")
      expect(cached_rack).to exist
    end

    it "copies gems from the local cache to the global cache" do
      gemfile <<-G
        source "#{source}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint"
      bundle :cache
      FileUtils.rm_r(default_bundle_path)
      FileUtils.rm_r(download_cache(source))
      expect(cached_gem("rack-1.0.0")).to exist

      bundle :install, :artifice => "endpoint_no_gem"
      should_be_installed "rack 1.0.0"
      expect(download_cache(source, "rack-1.0.0.gem")).to exist
    end

    describe "when installing gems from a different directory" do
      it "uses the global cache as a source" do
        install_gemfile <<-G, :artifice => "endpoint"
          source "#{source}"
          gem "rack"
          gem "activesupport"
        G

        # Both gems are installed and in the global cache
        should_be_installed "rack 1.0.0"
        should_be_installed "activesupport 2.3.5"
        expect(download_cache(source, "rack-1.0.0.gem")).to exist
        expect(download_cache(source, "activesupport-2.3.5.gem")).to exist
        FileUtils.rm_r(default_bundle_path)
        # Both gems are now only in the global cache
        should_not_be_installed "rack 1.0.0"
        should_not_be_installed "activesupport 2.3.5"

        install_gemfile <<-G, :artifice => "endpoint_no_gem"
          source "#{source}"
          gem "rack"
        G

        # rack is installed and both are in the global cache
        should_be_installed "rack 1.0.0"
        should_not_be_installed "activesupport 2.3.5"
        expect(download_cache(source, "rack-1.0.0.gem")).to exist
        expect(download_cache(source, "activesupport-2.3.5.gem")).to exist

        Dir.chdir bundled_app2 do
          create_file "gems.rb", Pathname.new(bundled_app2("gems.rb")), <<-G
            source "#{source}"
            gem "activesupport"
          G

          # Neither gem is installed and both are in the global cache
          should_not_be_installed "rack 1.0.0"
          should_not_be_installed "activesupport 2.3.5"
          expect(download_cache(source, "rack-1.0.0.gem")).to exist
          expect(download_cache(source, "activesupport-2.3.5.gem")).to exist

          # Install using the global cache instead of by downloading the .gem
          # from the server
          bundle :install, :artifice => "endpoint_no_gem"

          # activesupport is installed and both are in the global cache
          should_not_be_installed "rack 1.0.0"
          should_be_installed "activesupport 2.3.5"
          expect(download_cache(source, "rack-1.0.0.gem")).to exist
          expect(download_cache(source, "activesupport-2.3.5.gem")).to exist
        end
      end
    end
  end
end
