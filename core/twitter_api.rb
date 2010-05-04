#
# twitter_api.rb - Twitter API class
#
# Copyright (c) 2007, 2008 Katsuhiko Ichinose <ichi@users.sourceforge.jp>
#
# GNU General Public License version 2 is applied to this program.
#
# $Id: twitter_api.rb 164 2009-01-23 09:40:37Z ichi $
require 'net/http'
require 'thread'
require 'base64'
require 'io/wait'
miquire :lib, 'escape'

Net::HTTP.version_1_2

=begin
class TwitterAPI
=end
class TwitterAPI < Mutex
  HOST = 'twitter.com'
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 20
  FORMAT = 'json'
  API_MAX = 150
  API_RESET_INTERVAL = 3600

  @@failed_lock = Monitor.new
  @@last_success = nil

  def initialize(user, pass, &fail_trap)
    super()
    @user = user
    @pass = pass
    @getmutex = Mutex.new
    if(fail_trap) then
      @fail_trap = fail_trap
    else
      @fail_trap = nil
    end
  end

  def api_remain(response = nil)
    if response and response['X-RateLimit-Reset'] then
      @api_remain = [ response['X-RateLimit-Limit'].to_i,
                      response['X-RateLimit-Remaining'].to_i,
                      Time.at(response['X-RateLimit-Reset'].to_i) ]
    end
    return *@api_remain
  end

  def user
    @user
  end

  def connection
    http = Net::HTTP.new(HOST)
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    return http
  end

  def set_user(user)
    @user = user
  end

  def set_pass(pass)
    @pass = pass
  end

  def get(path, head)
    #self.lock()
    res = nil
    http = nil
    begin
      res = @getmutex.synchronize{
        http = self.connection()
        http.start
        http.get(path, head)
      }
    rescue Exception => evar
      res = evar
    ensure
      begin
        http.finish if http.active?
      rescue Exception => evar
        Log.warn('TwitterAPI.get:finish') do "#{evar.inspect}" end
      end
      #self.unlock()
    end
    notice "#{path} => #{res}"
    res
  end

  def get_with_auth(path, head_src)
    head = head_src.clone
    now = Time.now.getgm
    now_str = now.strftime('%Y/%m/%d %H:%M:%S +0000')
    auth = ["#{@user}:#{@pass}"].pack("m").chomp.gsub("\n", '')
    head['Authorization'] = "Basic #{auth}"
    res = get(path, head)
    if res.is_a?(Net::HTTPResponse) then
      limit, remain, reset = self.api_remain(res)
      if(res.code == '200') then
        Plugin::Ring::call(nil, :apiremain, self, remain, reset)
      elsif(res.code == '401') then
        if @fail_trap then
          last_success = @@last_success
          @@failed_lock.synchronize{
            if(@@last_success == last_success) then
              @@last_success = @fail_trap.call()
            end
            @user,@pass = *@@last_success
            res = self.get_with_auth(path, head_src)
          }
        end
      end
    end
    res
  end

  def post(path, data, head)
    #self.lock()
    res = nil
    http = nil
    begin
      res = @getmutex.synchronize{
        http = self.connection()
        http.start
        http.post(path, data, head)
      }
    rescue Exception => evar
      res = evar
    ensure
      begin
        http.finish if http.active?
      rescue Exception => evar
        Log.warn('TwitterAPI.post:finish') do "#{evar.inspect}" end
      end
      #self.unlock()
    end
    notice "#{path} => #{res}(#{data.inspect})"
    res
  end

  def post_with_auth(path, data, head)
    auth = ["#{@user}:#{@pass}"].pack("m").chomp.gsub("\n", '')
    head['Authorization'] = "Basic #{auth}"
    post(path, data, head)
  end

  def option_since(since)
    since.httpdate =~ /^(.*?), (\S+) (\S+) (\S+) (\S+) (\S+)/
    $1+'%2C+'+$2+'+'+$3+'+'+$4+'+'+$5+'+'+$6
  end

  def public_timeline(since = nil)
    path = '/statuses/public_timeline.' + FORMAT
    path += "?since_id=#{since}" if since
    head = {'Host' => HOST}
    get(path, head)
  end

  def friends_timeline(args = {})
    path = '/statuses/friends_timeline.' + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def replies(args = {})
    path = '/statuses/mentions.' + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def search(args = {})
    path = '/search.' + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get(path, head)
  end

  def retweeted_to_me(args = {})
    path = "/statuses/retweeted_to_me.#{FORMAT}" + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def friends(since = nil)
    path = '/statuses/friends.' + FORMAT
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def followers(args = {})
    path = '/statuses/followers.' + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def direct_messages(since = nil)
    path = '/direct_messages.' + FORMAT
    path += "?since=#{option_since(since)}" if since
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def user_show(args)
    path = "/users/show." + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get(path, head)
  end

  def status_show(args)
    path = "/statuses/show/#{args[:id]}.#{FORMAT}"
    head = {'Host' => HOST}
    get(path, head)
  end

  def rate_limit_status
    path = "/account/rate_limit_status.#{FORMAT}"
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def update(status, reply_to = nil)
    path = '/statuses/update.' + FORMAT
    enc = URI.encode(status, /[^a-zA-Z0-9\'\.\-\*\(\)\_]/n)
    data = 'status=' + enc
    data += '&in_reply_to_status_id=' + reply_to.to_s if reply_to
    # data += '&source=' + PROG_NAME
    head = {'Host' => HOST}
    post_with_auth(path, data, head)
  end

  def send(user, text)
    path = '/direct_messages/new.' + FORMAT
    data = "user=" + URI.encode(user)
    data += "&text=" + URI.encode(text)
    data += '&source=' + PROG_NAME
    head = {'Host' => HOST}
    res = post_with_auth(path, data, head)
    res
  end

  def favorite(id)
    path = "/favorites/create/#{id}." + FORMAT
    data = ''
    head = {'Host' => HOST}
    res = post_with_auth(path, data, head)
    res
  end

  def unfavorite(id)
    path = "/favorites/destroy/#{id}." + FORMAT
    data = ''
    head = {'Host' => HOST}
    res = post_with_auth(path, data, head)
    res
  end

  def follow(user)
    data = ''
    head = {'Host' => HOST}
    post_with_auth("/friendships/create/#{user[:id]}.#{FORMAT}", data, head)
  end

  def get_args(args)
    if not args.empty?
      "?" + args.map{|k, v| "#{Escape.uri_segment(k.to_s).to_s}=#{Escape.uri_segment(v.to_s).to_s}"}.join('&')
    else
      ''
    end
  end
end
