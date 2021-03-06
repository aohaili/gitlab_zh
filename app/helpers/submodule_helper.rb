module SubmoduleHelper
  include Gitlab::ShellAdapter

  VALID_SUBMODULE_PROTOCOLS = %w[http https git ssh].freeze

  # links to files listing for submodule if submodule is a project on this server
  def submodule_links(submodule_item, ref = nil, repository = @repository)
    url = repository.submodule_url_for(ref, submodule_item.path)

    if url == '.' || url == './'
      url = File.join(Gitlab.config.gitlab.url, @project.full_path)
    end

    if url =~ /([^\/:]+)\/([^\/]+(?:\.git)?)\Z/
      namespace, project = $1, $2
      project.rstrip!
      project.sub!(/\.git\z/, '')

      if self_url?(url, namespace, project)
        [namespace_project_path(namespace, project),
         namespace_project_tree_path(namespace, project, submodule_item.id)]
      elsif relative_self_url?(url)
        relative_self_links(url, submodule_item.id)
      elsif github_dot_com_url?(url)
        standard_links('github.com', namespace, project, submodule_item.id)
      elsif gitlab_dot_com_url?(url)
        standard_links('gitlab.com', namespace, project, submodule_item.id)
      else
        [sanitize_submodule_url(url), nil]
      end
    else
      [sanitize_submodule_url(url), nil]
    end
  end

  protected

  def github_dot_com_url?(url)
    url =~ /github\.com[\/:][^\/]+\/[^\/]+\Z/
  end

  def gitlab_dot_com_url?(url)
    url =~ /gitlab\.com[\/:][^\/]+\/[^\/]+\Z/
  end

  def self_url?(url, namespace, project)
    url_no_dotgit = url.chomp('.git')
    return true if url_no_dotgit == [Gitlab.config.gitlab.url, '/', namespace, '/',
                                     project].join('')
    url_with_dotgit = url_no_dotgit + '.git'
    url_with_dotgit == gitlab_shell.url_to_repo([namespace, '/', project].join(''))
  end

  def relative_self_url?(url)
    # (./)?(../repo.git) || (./)?(../../project/repo.git) )
    url =~ /\A((\.\/)?(\.\.\/))(?!(\.\.)|(.*\/)).*(\.git)?\z/ || url =~ /\A((\.\/)?(\.\.\/){2})(?!(\.\.))([^\/]*)\/(?!(\.\.)|(.*\/)).*(\.git)?\z/
  end

  def standard_links(host, namespace, project, commit)
    base = ['https://', host, '/', namespace, '/', project].join('')
    [base, [base, '/tree/', commit].join('')]
  end

  def relative_self_links(url, commit)
    # Map relative links to a namespace and project
    # For example:
    # ../bar.git -> same namespace, repo bar
    # ../foo/bar.git -> namespace foo, repo bar
    # ../../foo/bar/baz.git -> namespace bar, repo baz
    components = url.split('/')
    base = components.pop.gsub(/.git$/, '')
    namespace = components.pop.gsub(/^\.\.$/, '')

    if namespace.empty?
      namespace = @project.namespace.full_path
    end

    [
      namespace_project_path(namespace, base),
      namespace_project_tree_path(namespace, base, commit)
    ]
  end

  def sanitize_submodule_url(url)
    uri = URI.parse(url)

    if uri.scheme.in?(VALID_SUBMODULE_PROTOCOLS)
      uri.to_s
    else
      nil
    end
  rescue URI::InvalidURIError
    nil
  end
end
