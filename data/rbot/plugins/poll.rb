#-- vim:ts=2:et:sw=2
#++
#
# :title: Voting plugin for rbot
# Author:: David Gadling <dave@toasterwaffles.com>
# Copyright:: (C) 2010 David Gadling
# License:: BSD
#
# Submit a poll question to a channel, wait for glorious outcome.
#

class ::Poll
  attr_accessor :id, :author, :channel, :running, :ends_at, :started
  attr_accessor :question, :answers, :duration, :voters, :outcome

  def initialize(originating_message, question, answers, duration)
    @author = originating_message.sourcenick
    @channel = originating_message.channel
    @question = question
    @running = false
    @duration = duration

    @answers = Hash.new
    @voters  = Hash.new

    answer_index = "A"
    answers.each do |ans|
      @answers[answer_index] = {
        :value => ans,
        :count => 0
      }
      answer_index.next!
    end
  end

  def start!
    return if @running

    @started = Time.now
    @ends_at = @started + @duration
    @running = true
  end

  def stop!
    return if @running == false
    @running = false
  end

  def record_vote(voter, choice)
    if @running == false
      return "Poll's closed!"
    end

    if @voters.has_key? voter
      return "You already voted for #{@voters[voter]}!"
    end

    choice.upcase!
    if @answers.has_key? choice
      @answers[choice][:count] += 1
      @voters[voter] = choice

      return "Recorded your vote for #{choice}: #{@answers[choice][:value]}"
    else
      return "Don't have an option #{choice}"
    end
  end

  def printing_values
    return Hash[:question => @question, 
            :answers => @answers.keys.collect { |a| [a, @answers[a][:value]] }
    ]
  end

  def to_s
    return @question
  end

  def options
    options = "Options are: "
    @answers.each { |letter, info|
      options = options + "#{Bold}#{letter}#{NormalText}) #{info[:value]} "
    }
    return options
  end
end

class PollPlugin < Plugin
  Config.register Config::IntegerValue.new('poll.max_concurrent_polls',
    :default => 2,
    :desc => "How many polls a user can have running at once")
  Config.register Config::StringValue.new('poll.default_duration',
    :default => "2 minutes",
    :desc => "How long a poll will accept answers, by default.")
  Config.register Config::BooleanValue.new('poll.save_results',
    :default => true,
    :desc => "Should we save results until we see the nick of the pollster?")

  def init_reg_entry(sym, default)
    if @registry.has_key?(sym) == false
      @registry[sym] = default
    end
  end

  def initialize()
    super
    init_reg_entry :running, Hash.new
    init_reg_entry :archives, Hash.new
    init_reg_entry :last_poll_id, 0
  end

  MULTIPLIERS = {
    :seconds => 1,
    :minutes => 60,
    :hours   => 60*60,
    :days    => 24*60*60,
    :weeks   => 7*24*60*60
  }

  def authors_running_count(victim)
    return @registry[:running].values.collect { |p|
      if p.author == victim
        1
      else
        0
      end
    }.inject(0) { |acc, v| acc + v }
  end

  def start(m, params)
    author = m.sourcenick
    chan = m.channel

    max_concurrent = @bot.config['poll.max_concurrent_polls']
    if authors_running_count(author) == max_concurrent
      m.reply("Sorry, you're already at the limit (#{max_concurrent}) polls")
      return
    end

    input_blob = params[:blob].join(" ")
    quote_character = input_blob[0].chr()
    chunks = input_blob.split(/#{quote_character}\s+#{quote_character}/)
    if chunks.length <= 2
      m.reply("This isn't a dictatorship!")
      return
    end

    question = chunks[0].gsub(/"/, '')
    question = question + "?" if question[-1].chr != "?"
    answers = chunks[1, chunks.length()-1].map { |a| a.gsub(/"/, '') }

    params[:duration] = params[:duration].join(' ')
    if params[:duration] == ''
      target_duration = @bot.config['poll.default_duration']
    else
      target_duration = params[:duration]
    end

    val, units = target_duration.split(' ')
    if MULTIPLIERS.has_key? units.to_sym
      duration = val.to_i * MULTIPLIERS[units.to_sym]
    else
      m.reply("I don't understand the #{Bold}#{units}#{NormalText} unit")
      return
    end

    poll = Poll.new(m, question, answers, duration)

    m.reply "New poll from #{author}: #{Bold}#{question}#{NormalText}"
    m.reply poll.options

    poll.id = @registry[:last_poll_id] + 1
    poll.start!
    command = "poll vote #{poll.id} <SINGLE-LETTER>"
    m.reply("You have #{Bold}#{target_duration}#{NormalText} to: " +
            "#{Bold}/msg #{@bot.nick} #{command}#{NormalText} or " +
            "#{Bold}#{@bot.config['core.address_prefix']}#{command}#{NormalText} ")
    
    running = @registry[:running]
    running[poll.id] = poll
    @registry[:running] = running
    @bot.timer.add_once(duration) { count_votes(poll.id) }
    @registry[:last_poll_id] = poll.id
  end

  def count_votes(poll_id)
    poll = @registry[:running][poll_id]

    # Hrm, it vanished!
    return if poll == nil
    poll.stop!

    @bot.say(poll.channel, "Time to find the answer to: #{Bold}#{poll.question}#{NormalText}")

    sorted = poll.answers.sort { |a,b| b[1][:count]<=>a[1][:count] }

    winner_info = sorted.first
    winner_info << sorted.inject(0) { |accum, choice| accum + choice[1][:count] }

    if winner_info[2] == 0
      poll.outcome = "Nobody voted"
    else
      if sorted[0][1][:count] == sorted[1][1][:count]
        poll.outcome = "No clear winner: " +
          sorted.select { |a|
            a[1][:count] > 0
          }.collect { |a|
            "'#{a[1][:value]}' got #{a[1][:count]} vote#{a[1][:count] > 1 ? 's' : ''}"
          }.join(", ")
      else
        winning_pct = "%3.0f%%" % [ 100 * (winner_info[1][:count] / winner_info[2]) ]
        poll.outcome = "The winner was choice #{winner_info[0]}: " +
                       "'#{winner_info[1][:value]}' " +
                       "with #{winner_info[1][:count]} " +
                       "vote#{winner_info[1][:count] > 1 ? 's' : ''} (#{winning_pct})"
      end
    end

    @bot.say poll.channel, poll.outcome

    # Now that we're done, move it to the archives
    archives = @registry[:archives]
    archives[poll_id] = poll
    @registry[:archives] = archives

    # ... and take it out of the running list
    running = @registry[:running]
    running.delete(poll_id)
    @registry[:running] = running
  end

  def list(m, params)
    if @registry[:running].keys.length == 0
      m.reply("No polls running right now")
      return
    end

    @registry[:running].each { |id, p|
      m.reply("#{p.author}'s poll \"#{p.question}\" (id ##{p.id}) runs until #{p.ends_at}")
    }
  end

  def record_vote(m, params)
    poll_id = params[:id].to_i
    if @registry[:running].has_key?(poll_id) == false
      m.reply("I don't have poll ##{poll_id} running :(")
      return
    end

    running = @registry[:running]

    poll = running[poll_id]
    result = poll.record_vote(m.sourcenick, params[:choice])

    running[poll_id] = poll
    @registry[:running] = running
    m.reply result
  end

  def info(m, params)
    params[:id] = params[:id].to_i
    if @registry[:running].has_key? params[:id]
      poll = @registry[:running][params[:id]]
    elsif @registry[:archives].has_key? params[:id]
      poll = @registry[:archives][params[:id]]
    else
      m.reply "Sorry, couldn't find poll ##{Bold}#{params[:id]}#{NormalText}"
      return
    end

    to_reply = "Poll ##{poll.id} was asked by #{Bold}#{poll.author}#{NormalText} " +
               "in #{Bold}#{poll.channel}#{NormalText} #{poll.started}."
    if poll.running
      to_reply += " It's still running!"
      if poll.voters.has_key? m.sourcenick
        to_reply += " Be patient, it'll end #{poll.ends_at}"
      else
        to_reply += " You have until #{poll.ends_at} to vote if you haven't!"
        to_reply += " #{poll.options}"
      end
    else
      to_reply += " #{poll.outcome}"
    end

    m.reply to_reply
  end

  def help(plugin,topic="")
    case topic
    when "start"
      "poll start 'my question' 'answer1' 'answer2' ['answer3' ...] " +
      "[for 5 minutes] : Start a poll for the given duration. " +
      "If you don't specify a duration the default will be used."
    when "list"
      "poll list : Give some info about currently active polls"
    when "info"
      "poll info #{Bold}id#{Bold} : Get info about /results from a given poll"
    when "vote"
      "poll vote #{Bold}id choice#{Bold} : Vote on the given poll with your choice"
    else
      "Hold informative polls: poll start|list|info|vote"
    end
  end
end

plugin = PollPlugin.new
plugin.map 'poll start *blob [for *duration]', :action => 'start'
plugin.map 'poll list', :action => 'list'
plugin.map 'poll info :id', :action => 'info'
plugin.map 'poll vote :id :choice', :action => 'record_vote', :threaded => true
