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

            if cookie_str =~ /[;\s]domain=/i
              cookie_str.gsub(/(\s*;\s*)domain=[^;]*/i, "\\1Domain=#{COOKIE_DOMAIN_VALUE}")
            else
              "#{cookie_str}; Domain=#{COOKIE_DOMAIN_VALUE}"
            end
          end
        headers["Set-Cookie"] = (original_cookies + extra_cookies).join("\n") if extra_cookies.any?
      end

      [status, headers, body]
    end
  end

  Rails.configuration.middleware.insert_before(ActionDispatch::Cookies, ::CookieDomainMiddleware)

  after_initialize do
    Rails.logger.info "[CookieDomain] DISCOURSE_COOKIE_DOMAIN=#{COOKIE_DOMAIN_VALUE.inspect}"
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
  end
end
