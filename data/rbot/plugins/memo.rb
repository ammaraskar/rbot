#-- vim:ts=4:et
#++
#
# :title: memo plugin for rbot
# Author:: David Gadling <dave@toasterwaffles.com>
# Copyright:: (C) 2008 David Gadling
# License:: BSD
#
# Leave a memo for another user; the bot will PM it to them, the next time they
# see them, probably after some delay.
#

define_structure :Memo, :sender, :message, :date

class MemoPlugin < Plugin
    Config.register Config::IntegerValue.new('memo.delay',
        :default => 5,
        :desc => "The delay between when a user comes in the channel, and when we bug them if they have messages waiting")
    Config.register Config::IntegerValue.new('memo.memobox_size',
        :default => 20,
        :desc => "The size of a users memobox")

    def help(plugin, topic="")
        case topic
        when 'sending'
            _("memo to <user> <message> => Leave a memo for <user>, <user> is case INsensitive")
        when 'listing'
            _("'memo count' && list => do what you'd expect")
        when 'reading'
            _("read => read your next memo")
        else
            _("memo: memo plugin, leave a short note for other people. topics: sending, listing, reading")
        end
    end

    def interval_to_s(time_period)
        outList = []

        interval_array = [ [:wk, 604800], [:day, 86400], [:hr, 3600], [:min, 60] ]
        interval_array.each do |sub|
            if time_period >= sub[1] then
                time_val, time_period = time_period.divmod( sub[1] )
                name = sub[0].to_s
                outList.push(time_val.to_s + " #{name}")
            end
        end
        outList.push(time_period.to_i.to_s + " sec")
        return outList.join(" ")+" ago"
    end

    def memo_to_s(memo)
        age = interval_to_s(Time.now.to_f - memo.date.to_f)
        return "From #{memo.sender}, #{age}: #{memo.message}"
    end

    def memo_to_short_s(memo)
        age = interval_to_s(Time.now.to_f - memo.date.to_f)
        return "#{memo.sender} (#{age})"
    end

    def leaveMessage(m, params)
        victim = params[:recipient].downcase

        @bot.server.channels.each do |c|
            if c.user_nicks().include?(victim)
                m.reply("#{victim} is in #{c}! Go say hi!")
                return
            end
        end

        messages = @registry[victim] || Array.new

        msg = Memo.new(m.sourcenick, params[:msg].to_s, Time.now.to_f)
        messages.push(msg)

        @registry[victim] = messages
        @bot.okay m.sourcenick
    end

    def myMemoCount(m, params)
        victim = m.sourcenick
        myMessages = @registry[victim] || Array.new
        count = myMessages.length()

        if count > 0
            m.reply("You have #{count} memos waiting")
        else
            m.reply("You don't have any memos; how sad :(")
        end
    end

    def tellMemoCount(target)
        myMessages = @registry[target] || Array.new
        count = myMessages.length()

        if myMessages.length() > 0
            @bot.notice(target, "Hi, you have #{myMessages.length()} memos waiting, ask me for 'help memo' if you're not sure what to do next")
        end
    end

    def myMemoList(m, params)
        victim = m.sourcenick
        myMessages = @registry[victim] || Array.new

        if myMessages.length() == 0
            m.reply("You don't have any memos")
        else
            m.reply("#{myMessages.length()} memos: "+myMessages.map { |x| memo_to_short_s(x) }.join(", "))
        end
    end

    def getMyNextMemo(m, params)
        victim = m.sourcenick
        myMessages = @registry[victim] || Array.new

        if myMessages.length() == 0
            m.reply("You don't have any more memos")
        else
            m.reply(memo_to_s(myMessages.shift))
            @registry[victim] = myMessages
        end
    end

    def listen(m)
        return unless m.source
        victim = ""

        case m
        when NickMessage
            victim = m.newnick.downcase
        when JoinMessage
            victim = m.sourcenick.downcase
        end

        if victim == ""
            return
        end

        theirMessages = @registry[victim] || Array.new
        if theirMessages.length() > 0
            @bot.timer.add_once(@bot.config['memo.delay']) { tellMemoCount(victim) }
        end
    end
end

# This plugin routing stuff is awesome and creepy at the same time.
# The wildcarded routes need to go last so that more specific commands (e.g.
# hof) get matched first
plugin = MemoPlugin.new
plugin.map 'memo to :recipient *msg', :action => :leaveMessage
plugin.map 'memo count', :action => :myMemoCount
plugin.map 'list', :action => :myMemoList
plugin.map 'read', :action => :getMyNextMemo
