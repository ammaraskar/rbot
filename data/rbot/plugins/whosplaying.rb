#-- vim:ts=4:et
#++
#
# :title: whosplaying plugin for rbot
# Author:: David Olbersen <dave@toasterwaffles.com>
# Copyright:: (C) 2008 David Olbersen
# License:: BSD
#
# Shows which users are currently playing what games
#

# Control codes
Norm = "\002\00302"
Hi = "\002\00313"
#Clear = "\017"
Clear = "\003\002"

class WhosPlaying < Plugin
    Config.register Config::IntegerValue.new('whosplaying.timeout',
        :default => 6*60*60,
        :validate => Proc.new { |v| (1..(24*60*60)).include? v },
        :desc => "How long until entries in the database timeout")

    def initialize()
        super
        @registry.set_default({})
        if @registry.has_key?('**timeout')
            @bot.config['whosplaying.timeout'] = @registry['**timeout']
            @registry.delete('**timeout')
        end
    end

    # return help, natch
    def help(plugin, topic="")
        case topic
        when 'playing'
            _("playing <what you're up to> => record yourself as playing something")
        when 'whosplaying'
            _("whosplaying => see what everybody else is playing")
        else
            _("whosplaying: whosplaying plugin. topics: playing, whosplaying")
        end
    end


    def startPlaying(m, params)
        updateDatabase(m)
        player = m.sourcenick.to_s
        foo = @registry[player] || Hash.new
        foo[:game] = params[:input].to_s
        foo[:started] = Time.now
        @registry[player] = foo
        @bot.notice(m.sourcenick.to_s, "You're now shown as playing #{Hi}#{params[:input]}")
        m.reply("Currently #{@registry.length} players in the whosplaying database")
    end


    def stopPlaying(m, params)
        @registry.delete(m.sourcenick.to_s)
        updateDatabase(m)
        @bot.notice(m.sourcenick.to_s, "You're no longer in the whosplaying database")
    end


    def intervalToString(dt)
        seconds = dt % 60
        dt = (dt - seconds) / 60
        minutes = dt % 60
        dt = (dt - minutes) / 60
        hours = dt % 24
        dt = (dt - hours) / 24
        days = dt % 7
        weeks = (dt - days) / 7

        rtn = []
        rtn.push("%d weeks" % weeks) if weeks != 0
        rtn.push("%d days" % days) if days != 0
        rtn.push("%d hours" % hours) if hours != 0
        rtn.push("%d minutes" % minutes) if minutes != 0
        rtn.push("%d seconds" % seconds)

        return rtn.join(" ")
    end

    def listPlayers(m, params)
        updateDatabase(m)
        asker = m.sourcenick.to_s
        tf = Time.new
        if @registry.length > 0
            tmp = @registry.to_hash
            @bot.notice(asker, "Currently #{Hi}#{tmp.length}#{Clear} users " +
                               "in the whosplaying database:")
            tmp.each do |player|
                user = player[0]
                game = player[1][:game]
                time = intervalToString( tf - player[1][:started] )
                @bot.notice(asker, "#{Hi}#{user}#{Clear} has been playing " +
                         "#{Hi}#{game}#{Clear} for " +
                         "#{Hi}#{time}#{Clear}")
            end
        else
            @bot.notice(asker, "Whosplaying database is empty!")
        end
    end

    def updateDatabase(m)
        tmp = @registry.to_hash
        tf = Time.new
        tmp.each do |player|
            user = player[0]
            dt = tf - player[1][:started]
            if dt >= @bot.config['whosplaying.timeout']
                @registry.delete(user)
            end
        end
    end

    def timeout(m, params)
        if params[:timeout]
            @bot.config['whosplaying.timeout'] = params[:timeout].to_i
            m.okay
        else
            m.reply _("whosplaying will timeout entries after %{time} seconds") % {:time => @bot.config['whosplaying.timeout']}
        end
    end
end

# This plugin routing stuff is awesome and creepy at the same time.
# The wildcarded routes need to go last so that more specific commands (e.g.
# hof) get matched first
plugin = WhosPlaying.new
plugin.map 'playing *input', :action => 'startPlaying'
plugin.map 'playing', :action => 'stopPlaying'
plugin.map 'whosplaying', :action => 'listPlayers'
plugin.map 'whosplaying timeout', :action => "timeout"
plugin.map 'whosplaying timeout [:timeout]', :action => "timeout",
    :requirements => {:timeout => /^\d+$/}, :auth_path => ':other'

plugin.default_auth('timeout::other', false)
