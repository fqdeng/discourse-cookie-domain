# frozen_string_literal: true

# name: discourse-cookie-domain
# about: Sets cookie domain from DISCOURSE_COOKIE_DOMAIN environment variable
# version: 0.1
# authors: Discourse
#
# Configure via environment variable:
#   DISCOURSE_COOKIE_DOMAIN=.vibe-coding.sh

COOKIE_DOMAIN_VALUE = ENV["DISCOURSE_COOKIE_DOMAIN"]

if COOKIE_DOMAIN_VALUE.present?
  after_initialize do
    # Inject domain into session cookies via DiscourseCookieStore
    module ::CookieDomainSessionExtension
      def set_cookie(request, session_id, cookie)
        cookie[:domain] = COOKIE_DOMAIN_VALUE if Hash === cookie
        super
      end
    end

    unless ActionDispatch::Session::DiscourseCookieStore.ancestors.include?(
             ::CookieDomainSessionExtension,
           )
      ActionDispatch::Session::DiscourseCookieStore.prepend(::CookieDomainSessionExtension)
    end
  end

  # Middleware to inject domain into all non-session Set-Cookie headers
  class ::CookieDomainMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)

      if headers["set-cookie"].present?
        updated =
          headers["set-cookie"].split("\n").map do |cookie_str|
            if cookie_str !~ /[;\s]domain=/i
              "#{cookie_str}; Domain=#{COOKIE_DOMAIN_VALUE}"
            else
              cookie_str
            end
          end
        headers["set-cookie"] = updated.join("\n")
      end

      [status, headers, body]
    end
  end

  Rails.application.config.middleware.insert_after(ActionDispatch::Cookies, ::CookieDomainMiddleware)
end
