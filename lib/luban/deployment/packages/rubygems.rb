module Luban
  module Deployment
    module Packages
      class Rubygems < Luban::Deployment::Package::Base
        protected

        def self.get_latest_version; RubygemsUpdate.get_latest_version; end

        def setup_provision_tasks
          super
          provision_tasks[:install].switch :install_doc, "Install Rubygems document"
        end

        class Installer < Luban::Deployment::Package::Installer
          def install_doc?
            task.opts.install_doc
          end

          def package_path
            parent.package_path
          end

          def install_path
            parent.install_path
          end
          
          define_executable 'gem'
          
          def ruby_executable
            parent.ruby_executable
          end

          def src_file_extname
            @src_file_extname ||= 'tgz'
          end

          def source_repo
            @source_repo ||= "https://rubygems.org"
          end

          def source_url_root
            @source_url_root ||= "rubygems"
          end

          def installed?
            return false unless file?(gem_executable)
            match?("#{gem_executable} -v", package_version)
          end

          protected

          def configure_build_options
            super
            unless install_doc?
              if version_match?(package_version, ">=2.0.0")
                @configure_opts.push("--no-document")
              else
                @configure_opts.push('--no-rdoc', '--no-ri')
              end
            end
          end

          def validate
            if parent.nil?
              abort "Aborted! Parent package for Rubygems MUST be provided."
            end
            unless parent.is_a?(Ruby::Installer)
              abort "Aborted! Parent package for Rubygems MUST be an instance of #{Ruby::Installer.name}"
            end
          end

          def configure_package!
            test(ruby_executable, 
                 "setup.rb config >> #{install_log_file_path} 2>&1")
          end

          def make_package!
            test(ruby_executable, 
                 "setup.rb setup >> #{install_log_file_path} 2>&1")
          end

          def install_package!
            test(ruby_executable, 
                 "setup.rb install #{configure_opts.reject(&:empty?).join(' ')} >> #{install_log_file_path} 2>&1")
          end

          def update_binstubs!; end
        end
      end
    end
  end
end
