# name: discourse-cookie-domain
# about: Duplicates cookies to an additional domain from DISCOURSE_COOKIE_DOMAIN environment variable
# version: 0.2
# authors: Discourse
# frozen_string_literal: true
COOKIE_DOMAIN_VALUE = ENV["DISCOURSE_COOKIE_DOMAIN"]

# .present? 检查值是否存在且不为空字符串（Rails 提供的方法）
# 只有设置了环境变量时，才启用下面的功能
if COOKIE_DOMAIN_VALUE.present?

  # after_initialize 是 Discourse 插件的钩子，在应用初始化完成后执行里面的代码
  after_initialize do

    # 定义一个模块（module），用来扩展/覆盖 session cookie 的写入行为
    # :: 前缀表示在全局命名空间下定义，避免嵌套在其他模块内
    module ::CookieDomainSessionExtension

      # 重写 set_cookie 方法，参数：request=请求对象, session_id=会话ID, cookie=cookie数据
      def set_cookie(request, session_id, cookie)
        # super 调用原始的 set_cookie 方法，先正常写入原始 cookie
        super

        # Hash === cookie 检查 cookie 是否是哈希类型（即键值对结构）
        if Hash === cookie
          # .dup 创建 cookie 哈希的浅拷贝，避免修改原始对象
          extra_cookie = cookie.dup
          # 将副本的 :domain 键设置为我们配置的域名
          extra_cookie[:domain] = COOKIE_DOMAIN_VALUE
          # 通过 cookie_jar 将这个带新域名的 cookie 副本写入响应
          # @key 是父类中存储的 session cookie 名称
          cookie_jar(request)[@key] = extra_cookie
        end
      end
    end

    # .ancestors 返回类的继承链（包含所有 include/prepend 的模块）
    # .include?() 检查模块是否已经被混入，防止重复 prepend
    unless ActionDispatch::Session::DiscourseCookieStore.ancestors.include?(
             ::CookieDomainSessionExtension,
           )
      # prepend 将模块插入到类的方法查找链最前面
      # 这样调用 set_cookie 时会先执行我们模块中的版本
      ActionDispatch::Session::DiscourseCookieStore.prepend(::CookieDomainSessionExtension)
    end
  end

  # 定义一个 Rack 中间件类，用来拦截并复制所有 Set-Cookie 响应头
  # Rack 中间件是 Ruby Web 应用中处理 HTTP 请求/响应的管道组件
  class ::CookieDomainMiddleware

    # initialize 是构造函数，app 是中间件链中的下一个应用/中间件
    def initialize(app)
      @app = app  # 将下一个中间件保存为实例变量
    end

    # call 是中间件的入口方法，env 包含 HTTP 请求的所有环境信息
    def call(env)
      # 调用下一个中间件/应用，获取返回的 [状态码, 响应头, 响应体]
      status, headers, body = @app.call(env)

      # 检查响应头中是否有 set-cookie（即服务器要设置 cookie）
      if headers["set-cookie"].present?
        # 按换行符分割，每行是一个独立的 Set-Cookie 指令
        original_cookies = headers["set-cookie"].split("\n")
        # .map 遍历每个 cookie 字符串，生成一个带新域名的副本数组
        extra_cookies =
          original_cookies.map do |cookie_str|
            # =~ 是正则匹配运算符，检查 cookie 中是否已经有 domain= 属性
            if cookie_str =~ /[;\s]domain=/i
              # .gsub 是全局替换，用正则把已有的 domain=xxx 替换为新域名
              # \\1 引用第一个捕获组（分号和空格部分），保留原始格式
              cookie_str.gsub(/(\s*;\s*)domain=[^;]*/i, "\\1Domain=#{COOKIE_DOMAIN_VALUE}")
            else
              # 如果没有 domain 属性，直接在末尾追加 Domain=新域名
              "#{cookie_str}; Domain=#{COOKIE_DOMAIN_VALUE}"
            end
          end
        # 将原始 cookie 和新域名的副本合并，用换行符连接，写回响应头
        headers["set-cookie"] = (original_cookies + extra_cookies).join("\n")
      end

      # 返回 [状态码, 响应头, 响应体]，这是 Rack 中间件的标准返回格式
      [status, headers, body]
    end
  end

  # 将我们的中间件插入到 Rails 中间件栈中
  # insert_after 表示放在 ActionDispatch::Cookies 之后执行
  # 这样我们的中间件能拦截到所有 cookie 相关的响应头
  Rails.application.config.middleware.insert_after(ActionDispatch::Cookies, ::CookieDomainMiddleware)

end  # if COOKIE_DOMAIN_VALUE.present? 的结束