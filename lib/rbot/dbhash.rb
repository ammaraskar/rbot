#-- vim:sw=2:et
#++
#
# :title: Berkeley DB interface

begin
  require 'bdb'
rescue LoadError
  fatal "rbot couldn't load the bdb module, perhaps you need to install it? try: http://www.ruby-lang.org/en/raa-list.rhtml?name=bdb"
rescue Exception => e
  fatal "rbot couldn't load the bdb module: #{e.pretty_inspect}"
end

if not defined? BDB
  exit 2
end

if BDB::VERSION_MAJOR < 4
  fatal "Your bdb (Berkeley DB) version #{BDB::VERSION} is too old!"
  fatal "rbot will only run with bdb version 4 or higher, please upgrade."
  fatal "For maximum reliability, upgrade to version 4.2 or higher."
  raise BDB::Fatal, BDB::VERSION + " is too old"
end

if BDB::VERSION_MAJOR == 4 and BDB::VERSION_MINOR < 2
  warning "Your bdb (Berkeley DB) version #{BDB::VERSION} may not be reliable."
  warning "If possible, try upgrade version 4.2 or later."
end

# make BTree lookups case insensitive
module BDB
  class CIBtree < Btree
    def bdb_bt_compare(a, b)
      if a == nil || b == nil
        warning "CIBTree: comparing #{a.inspect} (#{self[a].inspect}) with #{b.inspect} (#{self[b].inspect})"
      end
      (a||'').downcase <=> (b||'').downcase
    end
  end
end

module Irc

  # DBHash is for tying a hash to disk (using bdb).
  # Call it with an identifier, for example "mydata". It'll look for
  # mydata.db, if it exists, it will load and reference that db.
  # Otherwise it'll create and empty db called mydata.db
  class DBHash

    # absfilename:: use +key+ as an actual filename, don't prepend the bot's
    #               config path and don't append ".db"
    def initialize(bot, key, absfilename=false)
      @bot = bot
      @key = key
      relfilename = @bot.path key
      relfilename << '.db'
      if absfilename && File.exist?(key)
        # db already exists, use it
        @db = DBHash.open_db(key)
      elsif absfilename
        # create empty db
        @db = DBHash.create_db(key)
      elsif File.exist? relfilename
        # db already exists, use it
        @db = DBHash.open_db relfilename
      else
        # create empty db
        @db = DBHash.create_db relfilename
      end
    end

    def method_missing(method, *args, &block)
      return @db.send(method, *args, &block)
    end

    def DBHash.create_db(name)
      debug "DBHash: creating empty db #{name}"
      return BDB::Hash.open(name, nil,
      BDB::CREATE | BDB::EXCL, 0600)
    end

    def DBHash.open_db(name)
      debug "DBHash: opening existing db #{name}"
      return BDB::Hash.open(name, nil, "r+", 0600)
    end

  end


  # DBTree is a BTree equivalent of DBHash, with case insensitive lookups.
  class DBTree
    @@env=nil
    # TODO: make this customizable
    # Note that it must be at least four times lg_bsize
    @@lg_max = 64*1024*1024
    # absfilename:: use +key+ as an actual filename, don't prepend the bot's
    #               config path and don't append ".db"
    def initialize(bot, key, absfilename=false)
      @bot = bot
      @key = key
      if @@env.nil?
        begin
          @@env = BDB::Env.open(@bot.botclass, BDB::INIT_TRANSACTION | BDB::CREATE | BDB::RECOVER, "set_lg_max" => @@lg_max)
          debug "DBTree: environment opened with max log size #{@@env.conf['lg_max']}"
        rescue => e
          debug "DBTree: failed to open environment: #{e.pretty_inspect}. Retrying ..."
          @@env = BDB::Env.open(@bot.botclass, BDB::INIT_TRANSACTION | BDB::CREATE |  BDB::RECOVER)
        end
        #@@env = BDB::Env.open(@bot.botclass, BDB::CREATE | BDB::INIT_MPOOL | BDB::RECOVER)
      end

      relfilename = @bot.path key
      relfilename << '.db'

      if absfilename && File.exist?(key)
        # db already exists, use it
        @db = DBTree.open_db(key)
      elsif absfilename
        # create empty db
        @db = DBTree.create_db(key)
      elsif File.exist? relfilename
        # db already exists, use it
        @db = DBTree.open_db relfilename
      else
        # create empty db
        @db = DBTree.create_db relfilename
      end
    end

    def method_missing(method, *args, &block)
      return @db.send(method, *args, &block)
    end

    def DBTree.create_db(name)
      debug "DBTree: creating empty db #{name}"
      return @@env.open_db(BDB::CIBtree, name, nil, BDB::CREATE | BDB::EXCL, 0600)
    end

    def DBTree.open_db(name)
      debug "DBTree: opening existing db #{name}"
      return @@env.open_db(BDB::CIBtree, name, nil, "r+", 0600)
    end

    def DBTree.cleanup_logs()
      begin
        debug "DBTree: checkpointing ..."
        @@env.checkpoint
      rescue Exception => e
        debug "Failed: #{e.pretty_inspect}"
      end
      begin
        debug "DBTree: flushing log ..."
        @@env.log_flush
        logs = @@env.log_archive(BDB::ARCH_ABS)
        debug "DBTree: deleting archivable logs: #{logs.join(', ')}."
        logs.each { |log|
          File.delete(log)
        }
      rescue Exception => e
        debug "Failed: #{e.pretty_inspect}"
      end
    end

    def DBTree.stats()
      begin
        debug "General stats:"
        debug @@env.stat
        debug "Lock stats:"
        debug @@env.lock_stat
        debug "Log stats:"
        debug @@env.log_stat
        debug "Txn stats:"
        debug @@env.txn_stat
      rescue
        debug "Couldn't dump stats"
      end
    end

    def DBTree.cleanup_env()
      begin
        debug "DBTree: checking transactions ..."
        has_active_txn = @@env.txn_stat["st_nactive"] > 0
        if has_active_txn
          warning "DBTree: not all transactions completed!"
        end
        DBTree.cleanup_logs
        debug "DBTree: closing environment #{@@env}"
        path = @@env.home
        @@env.close
        @@env = nil
        if has_active_txn
          debug "DBTree: keeping file because of incomplete transactions"
        else
          debug "DBTree: cleaning up environment in #{path}"
          BDB::Env.remove("#{path}")
        end
      rescue Exception => e
        error "failed to clean up environment: #{e.pretty_inspect}"
      end
    end

  end

end
