# frozen_string_literal: true

# name: discourse-cookie-domain
# about: Duplicates cookies to an additional domain from DISCOURSE_COOKIE_DOMAIN environment variable
# version: 0.2
# authors: Discourse
#
# Configure via environment variable:
#   DISCOURSE_COOKIE_DOMAIN=.vibe-coding.sh
#
# Original cookies are preserved as-is. An additional copy of each cookie
# is written with the configured domain.

COOKIE_DOMAIN_VALUE = ENV["DISCOURSE_COOKIE_DOMAIN"]

if COOKIE_DOMAIN_VALUE.present?
  after_initialize do
    # Duplicate session cookie to the configured domain
    module ::CookieDomainSessionExtension
      def set_cookie(request, session_id, cookie)
        super

        if Hash === cookie
          extra_cookie = cookie.dup
          extra_cookie[:domain] = COOKIE_DOMAIN_VALUE
          cookie_jar(request)[@key] = extra_cookie
        end
      end
    end

    unless ActionDispatch::Session::DiscourseCookieStore.ancestors.include?(
             ::CookieDomainSessionExtension,
           )
      ActionDispatch::Session::DiscourseCookieStore.prepend(::CookieDomainSessionExtension)
    end
  end

  # Middleware to duplicate all Set-Cookie headers with the configured domain
  class ::CookieDomainMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)

      if headers["set-cookie"].present?
        original_cookies = headers["set-cookie"].split("\n")
        extra_cookies =
          original_cookies.map do |cookie_str|
            # Duplicate the cookie with the new domain
            if cookie_str =~ /[;\s]domain=/i
              # Replace existing domain
              cookie_str.gsub(/(\s*;\s*)domain=[^;]*/i, "\\1Domain=#{COOKIE_DOMAIN_VALUE}")
            else
              "#{cookie_str}; Domain=#{COOKIE_DOMAIN_VALUE}"
            end
          end
        headers["set-cookie"] = (original_cookies + extra_cookies).join("\n")
      end

      [status, headers, body]
    end
  end

  Rails.application.config.middleware.insert_after(ActionDispatch::Cookies, ::CookieDomainMiddleware)
end
