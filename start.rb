#!/usr/bin/env ruby
require 'erb'
require 'excon'
require 'logger'
require 'json'
require 'rubygems'
require 'httparty'
$logger = Logger.new(STDOUT, ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO)

module Service
  class Base
    attr_reader :port
    attr_reader :address
    attr_reader :password
    def initialize(address,port,password)
      @address = address
      @port = port
      @password = password
    end

    def service_name
      self.class.name.downcase.split('::').last
    end

    def start
      ensure_directories
      $logger.info "starting #{service_name} on port #{port}"
    end

    def ensure_directories
      %w{lib run log}.each do |dir|
        path = "/var/#{dir}/#{service_name}"
        Dir.mkdir(path) unless Dir.exists?(path)
      end
    end

    def data_directory
      "/var/lib/#{service_name}"
    end

    def pid_file
      "/var/run/#{service_name}/#{port}.pid"
    end

    def executable
      self.class.which(service_name)
    end

    def stop
      $logger.info "stopping #{service_name} on port #{port}"
      if File.exists?(pid_file)
        pid = File.read(pid_file).strip
        begin
          self.class.kill(pid.to_i)
        rescue => e
          $logger.warn "couldn't kill #{service_name} on port #{port}: #{e.message}"
        end
      else
        $logger.info "#{service_name} on port #{port} was not running"
      end
    end

    def self.kill(pid, signal='SIGINT')
      Process.kill(signal, pid)
    end

    def self.fire_and_forget(*args)
      $logger.debug "running: #{args.join(' ')}"
      pid = Process.fork
      if pid.nil? then
        # In child
        exec args.join(" ")
      else
        # In parent
        Process.detach(pid)
      end
    end

    def self.which(executable)
      path = `which #{executable}`.strip
      if path == ""
        return nil
      else
        return path
      end
    end
  end

  class Proxy
    attr_reader :address
    attr_reader : port
    attr_reader : username
    attr_reader : password
    attr_reader : base64Password
    attr_reader : id
    def initialize(id,address,port,username,password,base64Password)
      @address = address
      @port = port
      @password = password
      @base64Password = base64Password
      @id = id
    end
    def start
      $logger.info "starting proxy with ip #{address} and port #{port}"
    end

    def stop
      $logger.info "stopping proxy with ip #{address} and port #{port}"
    end

    def restart
      stop
      sleep 5
      start
    end

    def test_url
      ENV['test_url'] || 'http://icanhazip.com'
    end

    def working?
      Excon.get(test_url, proxy: "http://#{username}:#{password}@#{address}:#{port}", :read_timeout => 10).status == 200
    rescue
      false
    end
  end

  class Haproxy < Base
    attr_reader :backends

    def initialize(port = 5566)
      @config_erb_path = "/usr/local/etc/haproxy.cfg.erb"
      @config_path = "/usr/local/etc/haproxy.cfg"
      @backends = []
      super(port)
    end

    def start
      super
      compile_config
      self.class.fire_and_forget(executable,
        "-f #{@config_path}",
        "| logger 2>&1")
    end

    def soft_reload
      self.class.fire_and_forget(executable,
        "-f #{@config_path}",
        "-p #{pid_file}",
        "-sf #{File.read(pid_file)}",
        "| logger 2>&1")
    end

    def add_backend(backend)
      @backends << {:name => 'proxy', :id => backend.id, :addr => backend.address, :port => backend.port, :password =>  backend.base64Password}
    end

    private
    def compile_config
      File.write(@config_path, ERB.new(File.read(@config_erb_path)).result(binding))
    end
  end
end
haproxy = Service::Haproxy.new
proxies = []
proxies_url = ENV['proxies_url']
proxies_json = HTTParty.get(proxies_url).body
parsed = JSON.parse(proxies_json) 
proxy_username = ENV['username']
proxy_password = ENV['password']
base64Password = system("echo -n #{proxy_username}:#{proxy_password} | openssl enc -a")
parsed.results.each { |p|
proxy = Service::Proxy.new(p.id,p.address,p.port,p.username,p.password,base64Password)
haproxy.add_backend(proxy)
proxy.start
proxies << proxy
}
haproxy.start

sleep 60

loop do
  $logger.info "testing proxies"
  proxies.each do |proxy|
    $logger.info "testing proxy #{proxy.address} (port #{proxy.port})"
    proxy.restart unless proxy.working?
  end
  $logger.info "sleeping for 60 seconds"
  sleep 60
end
