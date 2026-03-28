# frozen_string_literal: true

# name: discourse-cookie-domain
# about: Duplicates cookies to an additional domain from DISCOURSE_COOKIE_DOMAIN environment variable
# version: 0.3
# authors: Discourse
COOKIE_DOMAIN_VALUE = ENV["DISCOURSE_COOKIE_DOMAIN"]

Rails.logger.info "[CookieDomain] DISCOURSE_COOKIE_DOMAIN=#{COOKIE_DOMAIN_VALUE.inspect}"

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
          original_cookies.map do |cookie_str|
            if cookie_str =~ /[;\s]domain=/i
              cookie_str.gsub(/(\s*;\s*)domain=[^;]*/i, "\\1Domain=#{COOKIE_DOMAIN_VALUE}")
            else
              "#{cookie_str}; Domain=#{COOKIE_DOMAIN_VALUE}"
            end
          end
        headers["Set-Cookie"] = (original_cookies + extra_cookies).join("\n")
      end

      [status, headers, body]
    end
  end

  after_initialize do
    # Duplicate session cookie to the configured domain
    module ::CookieDomainSessionExtension
      def set_cookie(request, session_id, cookie)
        super

        if Hash === cookie
          extra_cookie = cookie.dup
          extra_cookie[:domain] = COOKIE_DOMAIN_VALUE
          Rails.logger.debug "[CookieDomain] SessionExtension: duplicating session cookie with Domain=#{COOKIE_DOMAIN_VALUE}"
          cookie_jar(request)[@key] = extra_cookie
        end
      end
    end

    unless ActionDispatch::Session::DiscourseCookieStore.ancestors.include?(
             ::CookieDomainSessionExtension,
           )
      ActionDispatch::Session::DiscourseCookieStore.prepend(::CookieDomainSessionExtension)
    end

    Rails.application.config.middleware.insert_before(ActionDispatch::Cookies, ::CookieDomainMiddleware)
    Rails.logger.info "[CookieDomain] Middleware registered before ActionDispatch::Cookies"
  end
else
  Rails.logger.warn "[CookieDomain] Plugin disabled: DISCOURSE_COOKIE_DOMAIN is not set"
end
