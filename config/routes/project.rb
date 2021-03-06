require 'constraints/project_url_constrainer'
require 'gitlab/routes/legacy_builds'

resources :projects, only: [:index, :new, :create]

draw :git_http

constraints(ProjectUrlConstrainer.new) do
  # If the route has a wildcard segment, the segment has a regex constraint,
  # the segment is potentially followed by _another_ wildcard segment, and
  # the `format` option is not set to false, we need to specify that
  # regex constraint _outside_ of `constraints: {}`.
  #
  # Otherwise, Rails will overwrite the constraint with `/.+?/`,
  # which breaks some of our wildcard routes like `/blob/*id`
  # and `/tree/*id` that depend on the negative lookahead inside
  # `Gitlab::PathRegex.full_namespace_route_regex`, which helps the router
  # determine whether a certain path segment is part of `*namespace_id`,
  # `:project_id`, or `*id`.
  #
  # See https://github.com/rails/rails/blob/v4.2.8/actionpack/lib/action_dispatch/routing/mapper.rb#L155
  scope(path: '*namespace_id',
        as: :namespace,
        namespace_id: Gitlab::PathRegex.full_namespace_route_regex) do
    scope(path: ':project_id',
          constraints: { project_id: Gitlab::PathRegex.project_route_regex },
          module: :projects,
          as: :project) do

      resources :autocomplete_sources, only: [] do
        collection do
          get 'members'
          get 'issues'
          get 'merge_requests'
          get 'labels'
          get 'milestones'
          get 'commands'
        end
      end

      #
      # Templates
      #
      get '/templates/:template_type/:key' => 'templates#show', as: :template

      resource  :avatar, only: [:show, :destroy]
      resources :commit, only: [:show], constraints: { id: /\h{7,40}/ } do
        member do
          get :branches
          get :pipelines
          post :revert
          post :cherry_pick
          get :diff_for_path
        end
      end

      resource :pages, only: [:show, :destroy] do
        resources :domains, only: [:show, :new, :create, :destroy], controller: 'pages_domains', constraints: { id: /[^\/]+/ }
      end

      resources :snippets, concerns: :awardable, constraints: { id: /\d+/ } do
        member do
          get :raw
          post :mark_as_spam
        end
      end

      resources :services, constraints: { id: /[^\/]+/ }, only: [:index, :edit, :update] do
        member do
          get :test
        end
      end

      resource :mattermost, only: [:new, :create]

      resources :deploy_keys, constraints: { id: /\d+/ }, only: [:index, :new, :create] do
        member do
          put :enable
          put :disable
        end
      end

      resources :forks, only: [:index, :new, :create]
      resource :import, only: [:new, :create, :show]

      resources :merge_requests, concerns: :awardable, constraints: { id: /\d+/ } do
        member do
          get :commits
          get :diffs
          get :conflicts
          get :conflict_for_path
          get :pipelines
          get :commit_change_content
          post :merge
          post :cancel_merge_when_pipeline_succeeds
          get :pipeline_status
          get :ci_environments_status
          post :toggle_subscription
          post :remove_wip
          get :diff_for_path
          post :resolve_conflicts
          post :assign_related_issues
        end

        collection do
          get :branch_from
          get :branch_to
          get :update_branches
          get :diff_for_path
          post :bulk_update
          get :new_diffs, path: 'new/diffs'
        end

        resources :discussions, only: [], constraints: { id: /\h{40}/ } do
          member do
            post :resolve
            delete :resolve, action: :unresolve
          end
        end
      end

      resources :variables, only: [:index, :show, :update, :create, :destroy]
      resources :triggers, only: [:index, :create, :edit, :update, :destroy] do
        member do
          post :take_ownership
        end
      end

      resources :pipelines, only: [:index, :new, :create, :show] do
        collection do
          resource :pipelines_settings, path: 'settings', only: [:show, :update]
          get :charts
        end

        member do
          get :stage
          post :cancel
          post :retry
          get :builds
          get :failures
          get :status
        end
      end

      resources :pipeline_schedules, except: [:show] do
        member do
          post :take_ownership
        end
      end

      resources :environments, except: [:destroy] do
        member do
          post :stop
          get :terminal
          get :metrics
          get '/terminal.ws/authorize', to: 'environments#terminal_websocket_authorize', constraints: { format: nil }
        end

        collection do
          get :folder, path: 'folders/*id', constraints: { format: /(html|json)/ }
        end

        resources :deployments, only: [:index] do
          member do
            get :metrics
          end
        end
      end

      resource :cycle_analytics, only: [:show]

      namespace :cycle_analytics do
        scope :events, controller: 'events' do
          get :issue
          get :plan
          get :code
          get :test
          get :review
          get :staging
          get :production
        end
      end

      scope '-' do
        resources :jobs, only: [:index, :show], constraints: { id: /\d+/ } do
          collection do
            post :cancel_all

            resources :artifacts, only: [] do
              collection do
                get :latest_succeeded,
                  path: '*ref_name_and_path',
                  format: false
              end
            end
          end

          member do
            get :status
            post :cancel
            post :retry
            post :play
            post :erase
            get :trace, defaults: { format: 'json' }
            get :raw
          end

          resource :artifacts, only: [] do
            get :download
            get :browse, path: 'browse(/*path)', format: false
            get :file, path: 'file/*path', format: false
            get :raw, path: 'raw/*path', format: false
            post :keep
          end
        end
      end

      Gitlab::Routes::LegacyBuilds.new(self).draw

      resources :hooks, only: [:index, :create, :edit, :update, :destroy], constraints: { id: /\d+/ } do
        member do
          get :test
        end

        resources :hook_logs, only: [:show] do
          member do
            get :retry
          end
        end
      end

      resources :container_registry, only: [:index, :destroy],
                                     controller: 'registry/repositories'

      namespace :registry do
        resources :repository, only: [] do
          resources :tags, only: [:destroy],
                           constraints: { id: Gitlab::Regex.container_registry_reference_regex }
        end
      end

      resources :milestones, constraints: { id: /\d+/ } do
        member do
          put :sort_issues
          put :sort_merge_requests
          get :merge_requests
          get :participants
          get :labels
        end
      end

      resources :labels, except: [:show], constraints: { id: /\d+/ } do
        collection do
          post :generate
          post :set_priorities
        end

        member do
          post :promote
          post :toggle_subscription
          delete :remove_priority
        end
      end

      resources :issues, concerns: :awardable, constraints: { id: /\d+/ } do
        member do
          post :toggle_subscription
          post :mark_as_spam
          get :referenced_merge_requests
          get :related_branches
          get :can_create_branch
          get :realtime_changes
          post :create_merge_request
        end
        collection do
          post  :bulk_update
        end
      end

      resources :project_members, except: [:show, :new, :edit], constraints: { id: /[a-zA-Z.\/0-9_\-#%+]+/ }, concerns: :access_requestable do
        collection do
          delete :leave

          # Used for import team
          # from another project
          get :import
          post :apply_import
        end

        member do
          post :resend_invite
        end
      end

      resources :group_links, only: [:index, :create, :update, :destroy], constraints: { id: /\d+/ }

      resources :notes, only: [:create, :destroy, :update], concerns: :awardable, constraints: { id: /\d+/ } do
        member do
          delete :delete_attachment
          post :resolve
          delete :resolve, action: :unresolve
        end
      end

      get 'noteable/:target_type/:target_id/notes' => 'notes#index', as: 'noteable_notes'

      resources :boards, only: [:index, :show] do
        scope module: :boards do
          resources :issues, only: [:index, :update]

          resources :lists, only: [:index, :create, :update, :destroy] do
            collection do
              post :generate
            end

            resources :issues, only: [:index, :create]
          end
        end
      end

      resources :todos, only: [:create]

      resources :uploads, only: [:create] do
        collection do
          get ":secret/:filename", action: :show, as: :show, constraints: { filename: /[^\/]+/ }
        end
      end

      resources :runners, only: [:index, :edit, :update, :destroy, :show] do
        member do
          get :resume
          get :pause
        end

        collection do
          post :toggle_shared_runners
        end
      end

      resources :runner_projects, only: [:create, :destroy]
      resources :badges, only: [:index] do
        collection do
          scope '*ref', constraints: { ref: Gitlab::PathRegex.git_reference_regex } do
            constraints format: /svg/ do
              get :build
              get :coverage
            end
          end
        end
      end
      namespace :settings do
        resource :members, only: [:show]
        resource :ci_cd, only: [:show], controller: 'ci_cd'
        resource :integrations, only: [:show]
        resource :repository, only: [:show], controller: :repository
      end

      # Since both wiki and repository routing contains wildcard characters
      # its preferable to keep it below all other project routes
      draw :wiki
      draw :repository
    end

    resources(:projects,
              path: '/',
              constraints: { id: Gitlab::PathRegex.project_route_regex },
              only: [:edit, :show, :update, :destroy]) do
      member do
        put :transfer
        delete :remove_fork
        post :archive
        post :unarchive
        post :housekeeping
        post :toggle_star
        post :preview_markdown
        post :export
        post :remove_export
        post :generate_new_export
        get :download_export
        get :activity
        get :refs
        put :new_issue_address
      end
    end
  end
end
