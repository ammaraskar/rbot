#-- vim:sw=2:et
#++
#
# :title: YouTube plugin for rbot
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2008 Giuseppe Bilotta

require 'json'

class YouTubePlugin < Plugin
  YOUTUBE_SEARCH = "http://gdata.youtube.com/feeds/api/videos?vq=%{words}&orderby=relevance"
  YOUTUBE_VIDEO = "https://www.googleapis.com/youtube/v3/videos?part=snippet%2Cstatistics%2CcontentDetails&id=%{id}&key=%{key}"

  YOUTUBE_VIDEO_URLS = %r{youtube.com/(?:watch\?(?:.*&)?v=|v/)(.*?)(&.*)?$}

  Config.register Config::IntegerValue.new('youtube.hits',
    :default => 3,
    :desc => "Number of hits to return from YouTube searches")
  Config.register Config::IntegerValue.new('youtube.descs',
    :default => 3,
    :desc => "When set to n > 0, the bot will return the description of the first n videos found")
  Config.register Config::BooleanValue.new('youtube.formats',
    :default => true,
    :desc => "Should the bot display alternative URLs (swf, rstp) for YouTube videos?")
  Config.register Config::BooleanValue.new('youtube.auto_info',
    :default => false,
    :desc => "Should the bot automatically detect YouTube URLs and reply with some info about them?")
  Config.register Config::StringValue.new('youtube.api_key',
    :default => "",
    :desc => "Youtube API v3 key generated from https://developers.google.com/youtube/registering_an_application")

  def youtube_filter(s)
    loc = Utils.check_location(s, /youtube\.com/)
    return nil unless loc
    if s[:text].include? '<link rel="alternate" type="text/xml+oembed"'
      vid = @bot.filter(:"youtube.video", s)
      return nil unless vid
      content = _("Category: %{cat}. Rating: %{rating}. Author: %{author}. Duration: %{duration}. %{views} views, faved %{faves} times. %{desc}") % vid
      return vid.merge(:content => content)
    elsif s[:text].include? '<!-- start search results -->'
      vids = @bot.filter(:"youtube.search", s)[:videos]
      if !vids.empty?
        return nil # TODO
      end
    end
    # otherwise, just grab the proper div
    if defined? Hpricot
      content = (Hpricot(s[:text])/".watch-video-desc").to_html.ircify_html
    end
    # suboptimal, but still better than the default HTML info extractor
    dm = /<div\s+class="watch-video-desc"[^>]*>/.match(s[:text])
    content ||= dm ? dm.post_match.ircify_html : '(no description found)'
    return {:title => s[:text].ircify_html_title, :content => content}
  end

  def youtube_apivideo_filter(s)
    debug s
    video_item = s["items"].first

    vid = {
      :formats => [],
      :author => (video_item["snippet"]["channelTitle"] rescue nil),
      :title =>  (video_item["snippet"]["title"] rescue nil),
      :desc =>   (video_item["snippet"]["description"] rescue nil),
      :seconds => (parse_iso8601_duration_hack(video_item["contentDetails"]["duration"]) rescue nil),
      :likes => (video_item["statistics"]["likeCount"] rescue nil),
      :dislikes => (video_item["statistics"]["dislikeCount"] rescue nil),
      :views => (video_item["statistics"]["viewCount"] rescue nil),
      :faves => (video_item["statistics"]["favoriteCount"] rescue nil)
    }
    if vid[:desc]
      vid[:desc].gsub!(/\s+/m, " ")
    end
    if secs = vid[:seconds]
      vid[:duration] = Utils.secs_to_short(secs)
    else
      vid[:duration] = _("unknown duration")
    end
    debug vid
    return vid
  end

  def parse_iso8601_duration_hack(s)
    duration_regex = %r{PT (?:(\d+)H)? (?:(\d+)M)? (?:(\d+)S)?}x
    if duration_regex.match(s)
      matches = duration_regex.match(s).captures
      hours = matches[0].to_i
      minutes = matches[1].to_i
      seconds = matches[2].to_i

      return seconds + (minutes * 60) + (hours * 60 * 60)
    else
      return nil
    end
  end


  def youtube_apisearch_filter(s)
    vids = []
    title = nil
    begin
      doc = REXML::Document.new(s[:text])
      title = doc.elements["feed/title"].text
      doc.elements.each("*/entry") { |e|
        vids << @bot.filter(:"youtube.apivideo", :rexml => e)
      }
      debug vids
    rescue => e
      debug e
    end
    return {:title => title, :vids => vids}
  end

  def youtube_search_filter(s)
    # TODO
    # hits = s[:hits] || @bot.config['youtube.hits']
    # scrap the videos
    return []
  end

  # Filter a YouTube video URL
  def youtube_video_filter(s)
    id = s[:youtube_video_id]
    if not id
      url = s.key?(:headers) ? s[:headers]['x-rbot-location'].first : s[:url]
      debug url
      id = YOUTUBE_VIDEO_URLS.match(url).captures.first rescue nil
    end
    return nil unless id

    debug id

    url = YOUTUBE_VIDEO % {:id => id, :key => @bot.config['youtube.api_key']}
    raw_json = @bot.httputil.get(url)

    debug raw_json

    response = JSON.parse(raw_json)
    begin
      return youtube_apivideo_filter(response)
    rescue => e
      debug e
      return nil
    end
  end

  def initialize
    super
    @bot.register_filter(:youtube, :htmlinfo) { |s| youtube_filter(s) }
    @bot.register_filter(:apisearch, :youtube) { |s| youtube_apisearch_filter(s) }
    @bot.register_filter(:apivideo, :youtube) { |s| youtube_apivideo_filter(s) }
    @bot.register_filter(:search, :youtube) { |s| youtube_search_filter(s) }
    @bot.register_filter(:video, :youtube) { |s| youtube_video_filter(s) }
  end

  def info(m, params)
    movie = params[:movie]
    id = nil
    if movie =~ /^[A-Za-z0-9]+$/
      id = movie.dup
    end

    vid = @bot.filter(:"youtube.video", :url => movie, :youtube_video_id => id)
    if vid
      str = _("%{bold}%{title}%{bold} [%{cat}] %{rating} @ %{url} by %{author} (%{duration}). %{views} views, faved %{faves} times. %{desc}") %
        {:bold => Bold}.merge(vid)
      if @bot.config['youtube.formats'] and not vid[:formats].empty?
        str << _("\n -- also available at: ")
        str << vid[:formats].inject([]) { |list, fmt|
          list << ("%{url} %{type} %{format} (%{duration} %{expression} %{medium})" % fmt)
        }.join(', ')
      end
      m.reply str
    else
      m.reply(_("couldn't retrieve video info") % {:id => id})
    end
  end

  def search(m, params)
    what = params[:words].to_s
    searchfor = CGI.escape what
    url = YOUTUBE_SEARCH % {:words => searchfor}
    resp, xml = @bot.httputil.get_response(url)
    unless Net::HTTPSuccess === resp
      m.reply(_("error looking for %{what} on youtube: %{e}") % {:what => what, :e => xml})
      return
    end
    debug "filtering XML"
    vids = @bot.filter(:"youtube.apisearch", DataStream.new(xml, params))[:vids][0, @bot.config['youtube.hits']]
    debug vids
    case vids.length
    when 0
      m.reply _("no videos found for %{what}") % {:what => what}
      return
    when 1
      show = "%{title} (%{duration}) [%{desc}] @ %{url}" % vids.first
      m.reply _("One video found for %{what}: %{show}") % {:what => what, :show => show}
    else
      idx = 0
      shorts = vids.inject([]) { |list, el|
        idx += 1
        list << ("#{idx}. %{bold}%{title}%{bold} (%{duration}) @ %{url}" % {:bold => Bold}.merge(el))
      }.join(" | ")
      m.reply(_("Videos for %{what}: %{shorts}") % {:what =>what, :shorts => shorts},
              :split_at => /\s+\|\s+/)
      if (descs = @bot.config['youtube.descs']) > 0
        vids[0, descs].each_with_index { |v, i|
          m.reply("[#{i+1}] %{title} (%{duration}): %{desc}" % v, :overlong => :truncate)
        }
      end
    end
  end

  def comma_numbers(number, delimiter = ',')
    number.to_s.reverse.gsub(%r{([0-9]{3}(?=([0-9])))}, "\\1#{delimiter}").reverse
  end

  def unreplied(m)
    return if @bot.config['youtube.auto_info'] == false
    return if m.action?

    escaped = URI.escape m.message, bot.plugins['url'].class::OUR_UNSAFE
    urls = URI.extract escaped, ['http', 'https']
    return if urls.length == 0

    movie = urls[0]
    vid = @bot.filter :"youtube.video", :url => movie
    return if vid == nil
    vid["views"] = comma_numbers(vid["views"])
    vid["likes"] = comma_numbers(vid["likes"])
    vid["dislikes"] = comma_numbers(vid["dislikes"])
    m.reply _("%{bold}%{title}%{bold} by %{author} (%{duration}). %{views} views. %{likes}/%{dislikes} likes/dislikes") % {:bold => Bold}.merge(vid)
  end

end

plugin = YouTubePlugin.new

plugin.map "youtube info :movie", :action => 'info', :threaded => true
plugin.map "youtube [search] *words", :action => 'search', :threaded => true
