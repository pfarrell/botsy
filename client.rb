class String
  def self.rand(size=16)
    s = ""
    size.times { s << (i = Kernel.rand(62); i += ((i < 10) ? 48 : ((i < 36) ? 55 : 61 ))).chr }
    return s
  end
end

class Response
  attr_accessor :command, :command_id, :host_id, :stdout, :stderr, :exitcode

  def initialize(host_id, command_id, command)
    @host_id= host_id
    @command_id = command_id
    @command = command
    @stdout = []
    @stderr = []
  end

  def to_json(opts={})
    return {:host_id=>@host_id, :command_id=>@command_id,  :command=>@command, :stdout=>@stdout, :stderr=>@stderr, :exitcode=>@exitcode}
  end
end

require 'open4'
require 'redis'
require 'yaml'
require 'json'
require 'socket'

def reply(resp)
  @comm.rpush($reply_queue, resp.to_json)
end

def do_command(command, resp)
  status=Open4::popen4(command.strip) do |pid, stdin, stdout,stderr|
    stdout.readlines.each do |line| 
      resp.stdout << line.chop
    end
  end
  resp.exitcode=status.exitstatus
  return resp
end

env = ENV["RACK_ENV"] || "production"
cfg = YAML.load_file('config/config.yml')[env]
@sub = Redis.new(:host=>cfg["redis"]["server"], :port=>cfg["redis"]["port"].to_i)
@comm = Redis.new(:host=>cfg["redis"]["server"], :port=>cfg["redis"]["port"].to_i)
host_id=String.rand(8)
$reply_queue = cfg["redis"]["client_channel"]
$command_queue = cfg["redis"]["command_queue"]
$pubsub = cfg["redis"]["master_channel"]

# host comm thread
pubsub=Thread.new {
  @sub.subscribe($pubsub) do |on|
    on.message do |channel, msg|
      msg=JSON.parse(msg)
      command = msg["command"]
      resp = Response.new(host_id, msg["id"], command)
      case command.strip
        when "s","status"
          resp.stdout << "here"
        when "client_shutdown"
          resp.stdout << "shutting down"
          exit
        else
          resp = Response.new(host_id,msg["id"], command)
          begin
            resp = do_command(command, resp)
          rescue Exception => ex
            resp.stderr << ex.message
          end
      end
      reply(resp.to_json)
    end   
  end
}

#worker thread
worker=Thread.new {
  while(true)
    if @comm.llen($command_queue) > 0
      str = @comm.lpop($command_queue)
      next if str.nil?
      cmd = JSON.parse(str)
      exit if cmd["command"].strip == "client_shutdown"
      resp = Response.new(host_id, cmd["id"], cmd["command"])
      begin
        resp=do_command(cmd["command"], resp)
      rescue Exception => ex
        resp.stderr << ex.message
      end
      reply(resp.to_json)
    else
      sleep 1
    end
  end
}
pubsub.join
worker.join
