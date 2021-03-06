module Luban
  module Deployment
    module Worker
      module Paths
        module Local
          def project_path
            @project_path ||= work_dir
          end

          def apps_path
            @apps_path ||= project_path.join('apps')
          end

          def app_path
            @app_path ||= apps_path.join(application)
          end
        end

        module Remote
          def deployment_projects_path
            @deployment_projects_path ||= luban_root_path.join('projects')
          end

          def releases_root_path
            @releases_root_path ||= luban_root_path.join('releases')
          end

          def env_path
            @env_path ||= luban_root_path.join('env')
          end

          def archives_path
            @archives_path ||= luban_root_path.join('archives')
          end
          alias_method :local_archives_path, :archives_path

          def tmp_path
            @tmp_path ||= luban_root_path.join('tmp')
          end

          def downloads_path
            @downloads_path ||= luban_root_path.join('downloads')
          end

          def docker_root_path
            @docker_root_path ||= luban_root_path.join('docker')
          end

          def project_path
            @project_path ||= env_path.join("#{stage}.#{project}")
          end

          def app_path
            @app_path ||= project_path.join(application)
          end

          def current_app_path
            @current_app_path ||= app_path.join('app')
          end

          def app_bin_path
            @app_bin_path ||= app_path.join('bin')
          end

          def app_tmp_path
            @app_tmp_path ||= app_path.join('tmp')
          end

          def shared_path
            @shared_path ||= app_path.join('shared')
          end

          def envrc_file
            @envrc_file ||= app_path.join(".envrc")
          end

          def unset_envrc_file
            @unset_envrc_file ||= app_path.join(".unset_envrc")
          end

          def packages_root_path
            @packages_root_path ||= luban_root_path.join('packages')
          end

          def app_archives_path
            @app_archives_path ||= 
              archives_path.join("#{stage}.#{project}", application, hostname)
          end

          def archived_logs_path
            @archived_logs_path ||= app_archives_path.join('archived_logs')
          end
        end
      end
    end
  end
end
