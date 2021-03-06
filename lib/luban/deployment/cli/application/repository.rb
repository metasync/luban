module Luban
  module Deployment
    class Application
      class Repository < Luban::Deployment::Worker::Base
        using Luban::CLI::CoreRefinements
        include Luban::Deployment::Worker::Paths::Local

        DefaultBundleJobs = 4
        DefaultRevisionSize = 12

        attr_reader :type
        attr_reader :from
        attr_reader :scm
        attr_reader :revision
        attr_reader :rev_size
        attr_reader :version

        def scm_module
          require_relative "scm/#{scm}"
          @scm_module ||= SCM.const_get(scm.camelcase)
        end

        def workspace_path
          @workspace_path ||= app_path.join('.luban')
        end

        def gems_path
          @gems_path ||= workspace_path.join('gems')
        end

        def clone_path
          @clone_path ||= workspace_path.join('repositories', type)
        end

        def releases_path
          @releases_path ||= workspace_path.join('releases', type)
        end

        def release_package_path
          @release_package_path ||= releases_path.join(release_package_file_name)
        end

        def release_package_file_name
          @release_package_file_name ||= "#{release_package_name}.#{release_package_extname}"
        end

        def release_package_name
          @release_package_name ||= "#{release_prefix}-#{release_tag}"
        end

        def release_package_extname
          @release_package_extname ||= 'tgz'
        end

        def release_prefix
          @release_prefix ||= "#{stage}-#{project}-#{application}-#{type}"
        end

        def release_tag
          @release_tag ||= "#{version}-#{revision}"
        end

        def release_name
          @release_name ||= "#{application}:#{type}:#{release_tag}"
        end

        def bundle_cmd
          return @bundle_cmd unless @bundle_cmd.nil?
          @bundle_cmd = fetch(:bundle_via, :bundle).tap do |cmd|
            if cmd.is_a?(Pathname) and !file?(cmd)
              abort "Aborted! Bundler command is NOT found: #{cmd}"
            end
          end
        end

        def bundle_without
          @bundle_without ||= %w(development test)
        end

        def bundle_jobs
          @bundle_jobs ||= DefaultBundleJobs
        end

        # Description on abstract methods:
        #   available?: check if the remote repository is available
        #   cloned?: check if the remote repository is cloned locally
        #   fetch_revision: retrieve the signature/checksum of the commit that will be deployed
        #   clone: clone a new copy of the remote repository
        #   update: update the clone of the remote repository
        #   release: copy the contents of cloned repository onto the release path
        [:available?, :cloned?, :fetch_revision, :clone, :update, :release].each do |method|
          define_method(method) do
            raise NotImplementedError, "#{self.class.name}##{__method__} is an abstract method."
          end
        end

        def build
          assure_dirs(clone_path, releases_path)
          if cloned? and !force?
            update_result "Skipped! Local #{type} repository has been built ALREADY.", status: :skipped
          else
            abort "Aborted! Remote #{type} repository is NOT available." unless available?
            if build!
              update_result "Successfully built local #{type} repository."
            else
              abort "FAILED to build local #{type} repository!"
            end
          end
        end

        def packaged?; file?(release_package_path); end

        def package
          abort "Aborted! Local #{type} repository is NOT built yet!" unless cloned?
          abort "Aborted! FAILED to update local #{type} repository!" unless update
          update_revision
          abort "Aborted! Version to package is MISSING!" if version.nil?
          release_package = ->{ { type: type, version: version, tag: release_tag,
                                  path: release_package_path, 
                                  md5: md5_for_file(release_package_path),
                                  bundled_gems: bundle_gems } }
          if packaged?
              if force?
                release
              else
                update_result "Skipped! ALREADY packaged #{release_name}.", status: :skipped,
                              release_pack: release_package.call
              end
          else
            release
            cleanup_releases
          end

          if packaged?
            update_result "Successfully packaged #{release_name} to #{release_package_path}."
          else
            abort "Aborted! FAILED to package #{release_name}!"
          end
          update_result release_pack: release_package.call
        end

        def deprecate
          abort "Aborted! Local #{type} repository is NOT built yet!" unless cloned?
          abort "Aborted! Version to deprecate is MISSING!" if version.nil?
          if file?(release_package_path)
            rm(release_package_path)
            update_result "Successfully deprecated packaged release #{release_name}."
          end
          update_result release_pack: { type: type, version: version, tag: release_tag }
        end

        protected

        def init
          @rev_size = DefaultRevisionSize
          task.opts.repository.each_pair { |k, v| instance_variable_set("@#{k}", v) }
          load_scm
          update_revision if cloned? and !version.nil?
        end

        def load_scm
          singleton_class.send(:prepend, scm_module)
        end

        def build!
          rmdir(clone_path)
          clone
        end

        def update_revision
          @revision = fetch_revision
        end

        def cleanup_releases(keep_releases = 1)
          cleanup_files(releases_path.join("#{release_prefix}-#{version}-*.#{release_package_extname}"),
                        keep_copies: keep_releases)
        end

        def release_with_gemfile?(gemfile_path)
          test(:tar, "-tzf #{release_package_path} #{gemfile_path} > /dev/null 2>&1")
        end

        def bundle_gems
          gemfile_path = Pathname.new(release_tag).join('Gemfile')
          gems_cache = Pathname.new('vendor').join('cache')
          bundle_path = Pathname.new('vendor').join('bundle')
          if release_with_gemfile?(gemfile_path)
            assure_dirs(gems_path)
            bundle_gems!(gemfile_path, gems_cache, bundle_path)
          else
            {}
          end
        end

        def bundle_gems!(gemfile_path, gems_cache, bundle_path)
          bundled_gems = {}
          gems = bundled_gems[:gems] = {}
          within(gems_path) do
            paths_to_extract = [gemfile_path, "#{gemfile_path}.lock", "#{release_tag}/vendor/gems"]
            execute(:tar, "--strip-components=1 -xzf #{release_package_path} #{paths_to_extract.join(' ')} > /dev/null 2>&1; true")
            options = []
            options << "--path #{bundle_path}"
            unless test(bundle_cmd, :check, *options)
              unless bundle_without.include?(stage.to_s)
                options << "--without #{bundle_without.join(' ')}"
              end
              options << "--jobs #{bundle_jobs} --quiet"
              if (output = capture(bundle_cmd, :install, *options)).empty?
                info "Successfully bundled gems in Gemfile"
              else
                abort "FAILED to bundle gems in Gemfile: #{output}"
              end
              if (output = capture(bundle_cmd, :package, "--all --quiet")).empty?
                info "Successfully packaged gems in Gemfile"
              else
                abort "Aborted! FAILED to package gems in Gemfile: #{output}"
              end
            end

            gem_files = capture(:ls, '-xtd', "#{gems_cache.join('*')} | grep -v \"md5$\"").split
            gem_files.each do |gem_file|
              gem_name = File.basename(gem_file)
              md5_file = gems_path.join("#{gem_file}.md5")
              gems[gem_name] =
                if file?(md5_file)
                  capture(:cat, md5_file)
                else
                  md5_for(gem_file).tap { |md5| execute(:echo, "#{md5} > #{md5_file}") }
                end
            end
          end
          gems_path.join(gems_cache).tap do |p|
            bundled_gems[:gems_cache] = { path: p, md5: md5_for_dir(p) }
          end
          gems_path.join('Gemfile.lock').tap do |p|
            bundled_gems[:locked_gemfile] = { path: p, md5: md5_for_file(p) }
          end
          bundled_gems
        end
      end
    end
  end
end
