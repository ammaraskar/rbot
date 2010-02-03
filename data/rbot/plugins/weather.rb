#-- vim:sw=2:et
#++
#
# :title: Weather plugin for rbot
#
# Author:: MrChucho (mrchucho@mrchucho.net): NOAA National Weather Service support
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2006 Ralph M. Churchill
# Copyright:: (C) 2006-2007 Giuseppe Bilotta
#
# License:: GPL v2

require 'rexml/document'

# Wraps NOAA National Weather Service information
class CurrentConditions
  @@bot = Irc::Utils.bot
    def initialize(station)
        @station = station
        @url = "http://www.nws.noaa.gov/data/current_obs/#{URI.encode @station.upcase}.xml"
        @current_conditions = String.new
    end
    def update
      begin
        resp = @@bot.httputil.get_response(@url)
        case resp
        when Net::HTTPSuccess
          cc_doc = (REXML::Document.new resp.body).root
          @current_conditions = parse(cc_doc)
        else
          raise Net::HTTPError.new(_("couldn't get data for %{station} (%{message})") % {
            :station => @station, :message => resp.message
          }, resp)
        end
      rescue => e
        if Net::HTTPError === e
          raise
        else
          error e
          raise "error retrieving data: #{e}"
        end
      end
      @current_conditions
    end
    def parse(cc_doc)
        cc = Hash.new
        cc_doc.elements.each do |c|
            cc[c.name.to_sym] = c.text
        end
        cc[:time] = cc[:observation_time_rfc822]
        cc[:wind] = cc[:wind_string]
        cc[:temperature] = cc[:temperature_string]
        cc[:heatindexorwindchill] = heat_index_or_wind_chill(cc)
        cc[:pressure] = cc[:pressure_string]

        _("At %{time} the conditions at %{location} (%{station_id}) were %{weather} with a visibility of %{visibility_mi}mi. The wind was %{wind} with %{relative_humidity}%% relative humidity. The temperature was %{temperature}%{heatindexorwindchill}, and the pressure was %{pressure}.") % cc
    end
private
    def heat_index_or_wind_chill(cc)
        hi = cc[:heat_index_string]
        wc = cc[:windchill_string]
        if hi and hi != 'NA' then
            _(" with a heat index of %{hi}") % { :hi => hi }
        elsif wc and wc != 'NA' then
            _(" with a windchill of %{wc}") % { :wc => wc }
        else
            ""
        end
    end
end

class WeatherPlugin < Plugin

  Config.register Config::BooleanValue.new('weather.advisory',
    :default => true,
    :desc => "Should the bot report special weather advisories when any is present?")
  Config.register Config::EnumValue.new('weather.units',
    :values => ['metric', 'english', 'both'],
    :default => 'both',
    :desc => "Units to be used by default in Weather Underground reports")


  Config.register Config::EnumValue.new('weather.reply_type',
    :values => ['public', 'private', 'notice', 'private notice'], :default => 'public',
    :desc => "Which method the bot should use to reply with weather info")

  def communicate(m, msg)
    case @bot.config['weather.reply_type'].intern
    when :private
      m.reply msg, :to => :private
    when :notice
      if m.private?
        m.notify msg
      else
        @bot.notice m.channel, msg
      end
    when :"private notice"
      m.notify msg
    else
      # Handle :public and unsupported values
      m.reply msg
    end
  end

  def help(plugin, topic="")
    case topic
    when "nws"
      "weather nws <station> => display the current conditions at the location specified by the NOAA National Weather Service station code <station> ( lookup your station code at http://www.nws.noaa.gov/data/current_obs/ )"
    when "station", "wu"
      "weather [<units>] <location> => display the current conditions at the location specified, looking it up on the Weather Underground site; you can use 'station <code>' to look up data by station code ( lookup your station code at http://www.weatherunderground.com/ ); you can optionally set <units>  to 'metric' or 'english' if you only want data with the units; use 'both' for units to go back to having both."
    else
      "weather information lookup. Looks up weather information for the last location you specified. See topics 'nws' and 'wu' for more information"
    end
  end

  def initialize
    super

    @nws_cache = Hash.new

    @wu_url         = "http://mobile.wunderground.com/cgi-bin/findweather/getForecast?brand=mobile%s&query=%s"
    @wu_station_url = "http://mobile.wunderground.com/auto/mobile%s/global/stations/%s.html"
  end

  def weather(m, params)
    if params[:where].empty?
      if @registry.has_key?(m.sourcenick)
        where = @registry[m.sourcenick]
        debug "Loaded weather info #{where.inspect} for #{m.sourcenick}"

        service = where.first.to_sym
        loc = where[1].to_s
        units = params[:units] || where[2] rescue nil
      else
        debug "No weather info for #{m.sourcenick}"
        communicate m, "I don't know where you are yet, #{m.sourcenick}. See 'help weather nws' or 'help weather wu' for additional help"
        return
      end
    else
      where = params[:where]
      if ['nws','station'].include?(where.first)
        service = where.first.to_sym
        loc = where[1].to_s
      else
        service = :wu
      end
    end

    if where.empty?
      debug "No weather location found for #{m.sourcenick}"
      communicate m, "I don't know where you are yet, #{m.sourcenick}. See 'help weather nws' or 'help weather wu' for additional help"
      return
    end

    wu_units = String.new
    if units
      case units.to_sym
      when :english, :metric
        wu_units = "_#{units}"
      when :both
      else
        communicate m, "Ignoring unknown units #{units}"
        wu_units = String.new
      end
    end

    case service
    when :nws
      nws_describe(m, where)
    when :station
      wu_station(m, where, wu_units)
    when :wu
      wu_weather(m, where, wu_units)
    when :google
      google_weather(m, where)
    else
      m.reply "I don't know the weather service #{service}, sorry"
      return
    end

    @registry[m.sourcenick] = [service, where, units]
  end

  def nws_describe(m, where)
    if @nws_cache.has_key?(where) then
        met = @nws_cache[where]
    else
        met = CurrentConditions.new(where)
    end
    if met
      begin
        communicate m, met.update
        @nws_cache[where] = met
      rescue Net::HTTPError => e
        m.reply _("%{error}, will try WU service") % { :error => e.message }
        wu_weather(m, where)
      rescue => e
        communicate m, e.message
      end
    else
      communicate m, "couldn't find weather data for #{where}"
    end
  end

  def wu_station(m, where, units="")
    begin
      xml = @bot.httputil.get(@wu_station_url % [units, CGI.escape(where)])
      case xml
      when nil
        communicate m, "couldn't retrieve weather information, sorry"
        return
      when /Search not found:/
        communicate m, "no such station found (#{where})"
        return
      when /<table border.*?>(.*?)<\/table>/m
        data = $1.dup
        communicate m, wu_weather_filter(data)
        wu_out_special(m, xml)
      else
        debug xml
        communicate m, "something went wrong with the data for #{where}..."
      end
    rescue => e
      communicate m, "retrieving info about '#{where}' failed (#{e})"
    end
  end

  def wu_weather(m, where, units="")
    begin
      xml = @bot.httputil.get(@wu_url % [units, CGI.escape(where)])
      case xml
      when nil
        communicate m, "couldn't retrieve weather information, sorry"
      when /City Not Found/
        communicate m, "no such location found (#{where})"
      when /Current<\/a>/
        data = ""
        xml.scan(/<table border.*?>(.*?)<\/table>/m).each do |match|
          data += wu_weather_filter(match.first)
        end
        if data.length > 0
          communicate m, data
        else
          communicate m, "couldn't parse weather data from #{where}"
        end
        wu_out_special(m, xml)
      when /<a href="\/auto\/mobile[^\/]+\/(?:global\/stations|[A-Z][A-Z])\//
        wu_weather_multi(m, xml)
      else
        debug xml
        communicate m, "something went wrong with the data from #{where}..."
      end
    rescue => e
      communicate m, "retrieving info about '#{where}' failed (#{e})"
    end
  end

  def wu_weather_multi(m, xml)
    # debug xml
    stations = xml.scan(/<td>\s*(?:<a href="([^?"]+\?feature=[^"]+)"\s*[^>]*><img [^>]+><\/a>\s*)?<a href="\/auto\/mobile[^\/]+\/(?:global\/stations|([A-Z][A-Z]))\/([^"]*?)\.html">(.*?)<\/a>\s*:\s*(.*?)<\/td>/m)
    # debug stations
    communicate m, "multiple stations available, use 'weather station <code>' or 'weather <city, state>' as appropriate, for one of the following (current temp shown):"
    stations.map! { |ar|
      warning = ar[0]
      loc = ar[2]
      state = ar[1]
      par = ar[3]
      w = ar[4]
      if state # US station
        (warning ? "*" : "") + ("%s, %s (%s): %s" % [loc, state, par, w.ircify_html])
      else # non-US station
        (warning ? "*" : "") + ("station %s (%s): %s" % [loc, par, w.ircify_html])
      end
    }
    communicate m, stations.join("; ")
  end

  def wu_check_special(xml)
    specials = []
    # We only scan the first half to prevent getting the advisories twice
    xml[0,xml.length/2].scan(%r{<a href="([^"]+\?[^"]*feature=warning#([^"]+))"[^>]*>([^<]+)</a>}) do
      special = {
        :url => "http://mobile.wunderground.com"+$1,
        :type => $2.dup,
        :special => $3.dup
      }
      spec_rx = Regexp.new("<a name=\"#{special[:type]}\">(?:.+?)<td align=\"left\">\\s+(.+?)\\s+</td>\\s+</tr>\\s+</table>", Regexp::MULTILINE)
      spec_xml = @bot.httputil.get(special[:url])
      if spec_xml and spec_td = spec_xml.match(spec_rx)
        special.merge!(:text => spec_td.captures.first.ircify_html)
      end
      specials << special
    end
    return specials
  end

  def wu_out_special(m, xml)
    return unless @bot.config['weather.advisory']
    specials = wu_check_special(xml)
    debug specials
    specials.each do |special|
      special.merge!(:underline => Underline)
      if special[:text]
        communicate m, ("%{underline}%{special}%{underline}: %{text}" % special)
      else
        communicate m, ("%{underline}%{special}%{underline} @ %{url}" % special)
      end
    end
  end

  def wu_weather_filter(stuff)
    result = Array.new
    if stuff.match(/<\/a>\s*Updated:\s*(.*?)\s*Observed at\s*(.*?)\s*<\/td>/)
      result << ("Weather info for %s (updated on %s)" % [$2.ircify_html, $1.ircify_html])
    end
    stuff.scan(/<tr>\s*<td>\s*(.*?)\s*<\/td>\s*<td>\s*(.*?)\s*<\/td>\s*<\/tr>/m) { |k, v|
      kk = k.riphtml
      vv = v.riphtml
      next if vv.empty?
      next if ["-", "- approx.", "N/A", "N/A approx."].include?(vv)
      next if kk == "Raw METAR"
      result << ("%s: %s" % [kk, vv])
    }
    return result.join('; ')
  end

  # TODO allow units choice other than lang, find how the API does it
  def google_weather(m, where)
    botlang = @bot.config['core.language'].intern
    if Language::Lang2Locale.key?(botlang)
      lang = Language::Lang2Locale[botlang].sub(/.UTF.?8$/,'')
    else
      lang = botlang.to_s[0,2]
    end

    debug "Google weather with language #{lang}"
    xml = @bot.httputil.get("http://www.google.com/ig/api?hl=#{lang}&weather=#{CGI.escape where}")
    debug xml
    weather = REXML::Document.new(xml).root.elements["weather"]
    begin
      error = weather.elements["problem_cause"]
      if error
        ermsg = error.attributes["data"]
        ermsg = _("no reason specified") if ermsg.empty?
        raise ermsg
      end
      city = weather.elements["forecast_information/city"].attributes["data"]
      date = Time.parse(weather.elements["forecast_information/current_date_time"].attributes["data"])
      units = weather.elements["forecast_information/unit_system"].attributes["data"].intern
      current_conditions = weather.elements["current_conditions"]
      foreconds = weather.elements.to_a("forecast_conditions")

      conds = []
      current_conditions.each { |el|
        name = el.name.intern
        value = el.attributes["data"].dup
        debug [name, value]
        case name
        when :icon
          next
        when :temp_f
          next if units == :SI
          value << "°F"
        when :temp_c
          next if units == :US
          value << "°C"
        end
        conds << value
      }

      forecasts = []
      foreconds.each { |forecast|
        cond = []
        forecast.each { |el|
          name = el.name.intern
          value = el.attributes["data"]
          case name
          when :icon
            next
          when :high, :low
            value << (units == :SI ? "°C" : "°F")
            value << " |" if name == :low
          when :condition
            value = "(#{value})"
          end
          cond << value
        }
        forecasts << cond.join(' ')
      }

      m.reply _("Google weather info for %{city} on %{date}: %{conds}. Three-day forecast: %{forecast}") % {
        :city => city,
        :date => date,
        :conds => conds.join(', '),
        :forecast => forecasts.join('; ')
      }
    rescue => e
      debug e
      m.reply _("Google weather failed: %{e}") % { :e => e}
    end

  end

end

plugin = WeatherPlugin.new
plugin.map 'weather :units :service *where',
  :defaults => {
    :where => false,
    :units => false,
    :service => false
  },
  :requirements => {
    :units => /metric|english|both/,
    :service => /wu|nws|station|google/
  }
