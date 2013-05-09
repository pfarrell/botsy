class String
  def self.rand(size=16)
    s = ""
    size.times { s << (i = Kernel.rand(62); i += ((i < 10) ? 48 : ((i < 36) ? 55 : 61 ))).chr }
    return s
  end
end

class Message
  attr_accessor :command, :id

  def initialize(opts={})
    @command = opts[:command]
    @id = String.rand(8)
  end

  def to_json(opts={})
    return {:command=>@command, :id=>@id}.to_json
  end
end

require 'redis'
require 'json'
require 'yaml'

cfg = YAML.load_file('config/config.yml')["development"]
$redis = Redis.new(:host=>cfg["redis"]["host"], :port=>cfg["redis"]["port"].to_i)
$client_channel = cfg["redis"]["client_channel"]
$command_queue = cfg["redis"]["command_queue"]
$master_channel = cfg["redis"]["master_channel"]

def broadcast(msg)
  $redis.publish($master_channel, Message.new(:command=>msg).to_json)
end

def enqueue(msg)
  $redis.rpush($command_queue, Message.new(:command=>msg).to_json)
end

def response
    resp = $redis.lpop($client_channel)
    return if resp.nil?
    r=JSON.parse(resp)
    print "#{r["host_id"]}:" 
    print " stdout: #{r["stdout"].inspect}"
    print " errors: #{r["stderr"].inspect}" if r["stderr"].size > 0
    print "\n"
    resp
end

def responses
  while(true)
    resp = response 
    break if resp.nil?
  end
end

def prompt
  puts "What is your command?"
  cmd = $stdin.gets
  case cmd.chop!
    when "q","exit", "quit" 
      exit
    when "r","responses"
      responses
    when "rc", "response_count"
      puts "#{$redis.llen($client_channel)} responses"
    when "pr", "pop_response"
      response 
    when "w","workload"
      puts "workload: #{$redis.llen($command_queue)}"
    when "e", "enqueue"
      cmd=$stdin.gets
      enqueue(cmd)
    when "clear"
      $redis.flushdb
    else
      broadcast(cmd)
  end
end


if ARGV[0] == "enqueue"
  $stdin.each_line do |line|
    enqueue(line)
  end
else
  while(true)
    prompt
  end
end

