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

  Rails.configuration.middleware.insert_before(ActionDispatch::Cookies, ::CookieDomainMiddleware)
end
