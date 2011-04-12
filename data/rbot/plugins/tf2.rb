#-- vim:sw=2:et
#++
#
# :title: Team Fortress 2 plugin for rbot
#
# Copier:: David Gadling <dave@toasterwaffles.com>
# Author:: Ole Christian Rynning <oc@rynning.no>
# Copyright:: (C) 2006 Ole Christian Rynning
# License:: GPL v2
#
# Simple Team Fortress 2 (Source Engine) plugin to query online
# servers to see if its online and kicking and how many users.
#
# Added 2 seconds timeout to the response. And sockets are now
# closing properly.

require 'socket'
require 'timeout'

class TF2Plugin < Plugin
  Config.register Config::ArrayValue.new('tf2.servers',
    :default => ['tf.joe.to', 'tf2.joe.to', 'tf3.joe.to', 'tf4.joe.to'],
    :desc => "A list of servers to check when using the !servers command")

  A2S_INFO = [-1, "TSource Engine Query"].pack("iZ*")

  TIMEOUT = 2

  def help(plugin, topic="")
    case topic
    when 'tf2'
      return _("tf2 <server> => return map name and number of players on the given server")
    when 'servers'
      return _("servers => same as saying !tf2 <server1> !tf2 <server2>...")
    when 'players'
      return _("players <server> => returns a list of players on server")
    end
    return _("tf2 topics: tf2, servers, players")
  end

  def getPlayerInfo(addr, port)
    socket = UDPSocket.new()
    begin
      toSend = [-1, 85, -1].pack("lcl")
      socket.send(toSend, 0, addr, port.to_i)
      response = nil

      timeout(TIMEOUT) do
        response = socket.recvfrom(1400,0)
      end
    rescue Exception => e
      error e
    end

    queryInfo = response.first.unpack("iAi")
    challengeNum = queryInfo[2]

    begin
      toSend = [-1, 85, challengeNum].pack("lcl")
      socket.send(toSend, 0, addr, port.to_i)
      response = nil

      timeout(TIMEOUT) do
        response = socket.recvfrom(1400*10,0)
      end
    rescue Exception => e
      error e
    end

    # Header format:
    #   int  showing if this packet is fragmented or not, normally not (-1), sometimes though (-2)
    #   byte showing response type, should be 'D'
    #   byte showing the number of players
    headerFormat = "iAc"

    # Player format:
    #   byte showing the index [0..num players] for this player
    #   string showing player's name
    #   long showing number of kills
    #   float showing time connected
    playerInfoFmt = "cZ*lf"

    decoded = response.first.unpack(headerFormat)
    wholePacket  = decoded[0] == -1
    goodResponse = decoded[1] == "D"
    playerCount  = decoded[2]

    allInfo = response.first.unpack(headerFormat + playerInfoFmt*playerCount)
    return allInfo[4, allInfo.length]
  end

  def players(m, params)
    addr = params[:conn_str]
    port = 27015
    playerInfo = []

    1.upto(3) {
      playerInfo = getPlayerInfo(addr, port)
      if playerInfo.length > 0
        break
      end
    }
    if playerInfo.length > 0
      toReport = []
      playerInfo.each_index { |i|
        if i % 4 == 0 and playerInfo[i] != ""
          toReport.push(playerInfo[i])
        end
      };
      @bot.notice(m.sourcenick, "%10s: %s" % [addr, toReport.join(" || ")])
    else
      @bot.notice(m.sourcenick, "%10s: either nobody playing or server down")
    end
  end

  def a2s_info(addr, port)
    socket = UDPSocket.new()
    begin
      socket.send(A2S_INFO, 0, addr, port.to_i)
      response = nil

      timeout(TIMEOUT) do
        response = socket.recvfrom(1400,0)
      end
    rescue Exception => e
      error e
    end

    socket.close()
    response ? response.first.unpack("iACZ*Z*Z*Z*sCCCaaCCZ*") : nil
  end

  def tf2(m, params)
    if params[:conn_str].include? ":"
      addr, port = params[:conn_str].split ":"
    else
      addr = params[:conn_str]
      port = 27015
    end
    info = nil
    1.upto(3) {
      info = a2s_info(addr, port)
      if info
        break
      end
    }
    if info
      players = "%2s/%2s" % [info[8], info[9]]
      map = info[4]
      server = "%10s" % addr
      if port == 27015
        m.reply _("#{server}: #{players} players on #{map}")
      else
        m.reply _("#{server}:#{port}: #{players} players on #{map}")
      end
    else
      m.reply "Couldn't connect to #{params[:conn_str]}"
    end
  end

  def servers(m, params)
      @bot.config['tf2.servers'].each { |box|
          tf2(m, {:conn_str => box})
      }
  end
end

plugin = TF2Plugin.new
plugin.map 'tf2 :conn_str', :thread => true
plugin.map 'servers', :thread => true
plugin.map 'players :conn_str', :thread => true
