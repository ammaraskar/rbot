#-- vim:sw=2:et
#++
#
# :title: fmylife.com quote retrieval
#
# Author:: David Gadling <dave@toasterwaffles.com>
#
# Copyright:: (C) 2009, David Gadling
#
# License:: public domain
#

require 'rexml/document'

class FMLPlugin < Plugin

  include REXML
  def help(plugin, topic="")
    [
      _("fml => print a random quote from fmylife.com"),
      _("fml id => print that quote from fmylife.com"),
      _("lml => print a random quote from lmylife.com"),
      _("lml id => print that quote from lmylife.com"),
      _("mlia id => print that quote from mylifeisaverage.com"),
    ].join(", ")
  end

  def fml_style_fetch(m, params)
    url = "http://%{domain}/view/%{id}/nocomment?key=4b3107ee53b5f&language=en" % {:id => params[:id], :domain => params[:domain]}
    xml = @bot.httputil.get(url)

    unless xml
      m.reply "Today, XML fetch failed. FML."
      return
    end
    doc = Document.new xml
    unless doc
      m.reply "Today, XML parse failed. FML."
      return
    end
    root = doc.elements['root'].elements['items'].elements['item']

    {
        :text => root.elements['text'].text,
        :id => root.attributes['id'],
        :agree => root.elements[params[:agree]].text,
        :deserved => root.elements[params[:deserved]].text,
        :bold => Bold, :green => Irc.color(:green), :red => Irc.color(:red),
    }
  end

  def fml(m, params)
    data = fml_style_fetch m, params.merge!({:domain => "api.betacie.com", :agree => "agree", :deserved => "deserved"})

    if data == nil
      return
    end

    reply = "%{text} %{bold}%{id}%{bold} %{green}%{agree} %{red}%{deserved}" % data
    m.reply reply
  end

  def gmh(m, params)
    data = fml_style_fetch m, params.merge!({:domain => "api.givesmehope.com", :agree => "yes", :deserved => "no"})

    if data == nil
      return
    end

    reply = "%{text} %{bold}%{id}%{bold} %{green}%{agree} %{red}%{deserved}" % data
    m.reply reply
  end

  def lml(m, params)
    id = params[:id]

    if id == 'random'
      url = "http://www.lmylife.com/?sort=random"
    else
      url = "http://www.lmylife.com/index.php?rant=#{id}"
    end

    html = @bot.httputil.get url
    quote = Utils.decode_html_entities html.scan(/<p>(.+?)<\/p>/)[0].to_s

    if id == 'random'
      id = html.scan(/rant=(\d+)/)[0].to_s
    end

    quote.gsub! /<[^>]*>/, ''
    quote.gsub! /\s{2,}/, ' '
    quote.gsub! /^\s*/, ''

    m.reply "#{quote.ircify_html} #{Bold}##{id}"
  end

  def mlia(m, params)
    id = params[:id]

    html = @bot.httputil.get "http://mylifeisaverage.com/story.php?id=#{id}"
    quote = Utils.decode_html_entities html.scan(/<span id="ls_contents-0">([^<]+)</)[0].to_s

    quote.gsub! /<br \/>/, ''

    m.reply "#{quote.ircify_html} #{Bold}##{id}"
  end
end

plugin = FMLPlugin.new

plugin.map "fml [:id]", :defaults => {:id => 'random'}
plugin.map "lml [:id]", :defaults => {:id => 'random'}
plugin.map "mlia :id", :requirements => {:id => /^\d+$/}
plugin.map "gmh [:id]", :defaults => {:id => 'random'}
