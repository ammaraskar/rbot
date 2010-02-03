#-- vim:sw=2:et
#++
#
# :title: Authserv management plugin for rbot
#
# Author:: David Gadling (anonj2) <dave@toasterwaffles.com>
#
# Copyright:: (C) 2008 David Gadling
#
# Automatically try to auth to AuthServ when connected

class AuthServPlugin < Plugin

  Config.register Config::StringValue.new('authserv.name',
    :default => "authserv",
    :desc => _("Name of the auth server"))

  Config.register Config::StringValue.new('authserv.command',
    :default => "auth",
    :desc => _("Command to send when identifying"))

  Config.register Config::StringValue.new('authserv.passwd',
    :default => "asdf123",
    :desc => _("Password to use when authenticating"))

  Config.register Config::StringValue.new('authserv.authenticated_string',
    :default => "I recognize you.",
    :desc => _("What authserv will say when you've authenticated successfully"))

  Config.register Config::StringValue.new('authserv.reply_from',
    :default => "authserv",
    :desc => _("The account you expect to get a reply from when authenticating"))

  def initialize()
    super
    @requestor = nil
  end

  def help(plugin, topic="")
    case topic
    when ""
      return _("authserv plugin: handles talking to authserv on connect")
    when "authserv"
      return _("authserv: manually authenticate to authserv")
    end
  end

  def do_auth(m, params)
    if m != nil
      @requestor = m.sourcenick
    end

    authServ = @bot.config['authserv.name']
    command  = @bot.config['authserv.command']
    pass     = @bot.config['authserv.passwd']
    @bot.say authServ, "#{command} #{pass}"
  end

  def connect
    do_auth(nil,nil)
  end

  def notice(m)
    return if m.sourcenick.downcase != @bot.config['authserv.reply_from'].downcase

    case m.message
    when @bot.config['authserv.authenticated_string']
      debug "we identified successfully to nickserv"
      if @requestor != nil:
        @bot.notice(@requestor, "We identified successfully to nickserv")
      end
    else
      if @requestor != nil:
        @bot.notice(@requestor, "Got message back from #{m.sourcenick}: #{m.message}")
      end
    end
  end

end

plugin = AuthServPlugin.new

plugin.map "authserv", :action => 'do_auth'
plugin.default_auth('*', false)

