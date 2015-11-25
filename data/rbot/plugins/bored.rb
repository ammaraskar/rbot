#-- vim:sw=2:et
#++
#
# :title: Bored plugin
#
# Author:: David Gadling <dave@toasterwaffles.com>
# Copyright:: (C) 2008 David Gadling
#
# I'm bored, give me a link to something interesting

class BoredPlugin < Plugin

  def help(plugin, topic="")
    case topic
    when "add"
      return "bored add <thing> => Add a thing (usually a link) to the database of things to do while bored"
    when "del"
      return "bored del <number> => Delete this item from the database"
    when "count"
      return "bored count => Get a count from the database"
    when "list"
      return "bored list => Gets a dump of the database ; bored list <start>-<stop> => Get the items between these numbers"
    end
    return "bored plugin: figure out something fun to do. Topics: add, del, count, list"
  end

  def addItem(m, params)
    toAdd = params[:item]

    items = @registry[:items] || Array.new

    if items.include?(toAdd)
      m.reply("I already have #{toAdd}")
      return
    end

    items.push(toAdd.to_s)
    @registry[:items] = items

    m.reply("Added item #{items.length}")
  end

  def delItem(m, params)
    victim = params[:id].to_s.to_i-1
    items = @registry[:items] || Array.new

    if items.length == 0
      m.reply("Nothing to delete!")
      return
    end

    if items.length < victim
      m.reply("I don't have anything at index #{victim+1}")
      return
    end

    deleted = items.delete_at(victim)

    @registry[:items] = items
    m.reply("Deleted item #{victim+1}, #{deleted}")
  end

  def getItem(m, params)
    items = @registry[:items] || Array.new

    if items.length == 0
      m.reply("I can't help, I don't have any advice")
      return
    end

    if params[:index] == nil
      victim = rand(items.length)
      m.reply("[#{victim+1}]: #{items[victim]}")
    else
      idx = params[:index].to_i - 1
      if items.length < idx
        m.reply _("Err, don't have that many items")
      else
        m.reply _("[#{params[:index]}]: #{items[idx]}")
      end
    end
  end

  def getCount(m, params)
    m.reply("I have #{@registry[:items].length} entries")
  end

  def getList(m, params)
    items = @registry[:items]
    m.reply("Database is empty!") if items == nil or items.length() == 0

    min = 0
    max = items.length-1
    shortStyle = false
    if params[:range] != nil
      range = params[:range].to_s.split("-")
      min = range[0].to_i-1
      if range.length > 1
        max = range[1].to_i-1
      end
    else
      shortStyle = true
    end

    if shortStyle == true
      m.reply(items.join(", "))
    else
      min.upto(max) do |i|
        m.reply("[#{i+1}]: #{items[i]}")
      end
    end
  end
end

plugin = BoredPlugin.new
plugin.map 'bored add :item', :action => :addItem
plugin.map 'bored del :id', :action => :delItem, :auth_path => 'del'
plugin.map 'bored count', :action => :getCount
plugin.map 'bored list :range', :action => :getList, :requirements => {:range => /^\d+-\d+/}
plugin.map 'bored list', :action => :getList
plugin.map 'bored [:index]', :action => :getItem

plugin.default_auth('bored::del', false)
