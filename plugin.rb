# frozen_string_literal: true

# name: discourse-cookie-domain
# about: Duplicates cookies to an additional domain from DISCOURSE_COOKIE_DOMAIN environment variable
# version: 0.3
# authors: Discourse
COOKIE_DOMAIN_VALUE = ENV["DISCOURSE_COOKIE_DOMAIN"]

if COOKIE_DOMAIN_VALUE.present?
  # Middleware to duplicate all Set-Cookie headers with the configured domain
  class ::CookieDomainMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)

      if headers["Set-Cookie"].present?
        original_cookies = headers["Set-Cookie"].split("\n")
        Rails.logger.debug "[CookieDomain] Middleware: found #{original_cookies.size} cookie(s) for #{env["REQUEST_PATH"]}"

        extra_cookies =
          original_cookies.filter_map do |cookie_str|
            next unless cookie_str.start_with?("_t=")

            duped =
              if cookie_str =~ /[;\s]domain=/i
                cookie_str.gsub(/(\s*;\s*)domain=[^;]*/i, "\\1Domain=#{COOKIE_DOMAIN_VALUE}")
              else
                "#{cookie_str}; Domain=#{COOKIE_DOMAIN_VALUE}"
              end

            duped = duped.gsub(/(\s*;\s*)SameSite=[^;]*/i, "") if duped =~ /[;\s]SameSite=/i
            duped = duped.gsub(/(\s*;\s*)Secure\b/i, "") if duped =~ /[;\s]Secure\b/i
            "#{duped}; SameSite=None; Secure"
          end
        headers["Set-Cookie"] = (original_cookies + extra_cookies).join("\n") if extra_cookies.any?
      end

      [status, headers, body]
    end
  end

  # Middleware to honour /login?redirect_url=... (and /signup?redirect_url=...) by
  # writing Discourse's native destination_url cookie before the request reaches
  # the controller. After a successful login Discourse reads this cookie and
  # redirects the user to the target URL.
  class ::LoginRedirectUrlMiddleware
    LOGIN_PATHS = %w[/login /signup].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      redirect_url = extract_redirect_url(env)
      status, headers, body = @app.call(env)

      if redirect_url
        cookie = "plugin_redirect_url=#{CGI.escape(redirect_url)}; Path=/; Secure; SameSite=Lax"
        existing = headers["Set-Cookie"]
        headers["Set-Cookie"] = existing.present? ? "#{existing}\n#{cookie}" : cookie
        Rails.logger.debug "[CookieDomain] LoginRedirect: set plugin_redirect_url for #{env["PATH_INFO"]}"
      end

      [status, headers, body]
    end

    private

    def extract_redirect_url(env)
      return nil unless env["REQUEST_METHOD"] == "GET"
      return nil unless LOGIN_PATHS.include?(env["PATH_INFO"])

      url = Rack::Request.new(env).params["redirect_url"]
      return nil if url.blank?

      # Strip CR/LF to prevent response header injection; otherwise accept as-is.
      url.delete("\r\n")
    end
  end

  Rails.configuration.middleware.insert_before(ActionDispatch::Cookies, ::CookieDomainMiddleware)
  Rails.configuration.middleware.insert_before(ActionDispatch::Cookies, ::LoginRedirectUrlMiddleware)
end
