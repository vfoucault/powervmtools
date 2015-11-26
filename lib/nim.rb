#
# Author:: Vianney Foucault (<vianney.foucault@gmail.com>)
# Copyright:: Copyright (c) 2015:: The Author
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'net/ssh'
require 'logger'
require_relative 'common'
module PowerVMTools
  ## $hmc_ssh is the SSH handled to run ssh command to the hmc from
  $nim_ssh = "empty"
  class NIM

    attr_accessor :name, :user, :passwd, :port
    attr_reader :log, :debug

    def initialize(name, options = {})
      @nimsettings = Hash.new
      @name = name
      @log = Logger.new(STDOUT)
      @log.level = Logger::INFO
      if options[:debug] == true
	@debug = true
        @log.level = Logger::DEBUG
      end	
      @log.debug("New NIM instance #{name}") 
      setupnim(name,options) 
    end

    def setupnim(name, options = {})
      @nimsettings = { :name => name,
		       :user => options[:user] || "root",
		       :passwd => options[:passwd] || nil,
		       :port => options[:port] || 22
		       }
      PowerVMTools::Common.testlink(@nimsettings[:name],@nimsettings[:user],@nimsettings[:passwd],{:port => @nimsettings[:port],:cmd => "lshmc -V"})
      $nim_ssh = Net::SSH.start( @nimsettings[:name],@nimsettings[:user], {:password => @nimsettings[:passwd],:port => @nimsettings[:port]})
    end

    def clientExists?(client)
      command = "odmget -q name=#{client} nim_object"
      output = self.run_command(command).chomp()  	
      if output.length > 0
	return true
      else
        return false
      end
    end

    def createclient(client)	
      ## will create a new nim client "client" is not yet defined
      unless clientExists?(client)
	command = "nim -o define -t standalone -a platform=chrp -a if1=\"find_net #{client} 0\" -a cable_type1=tp -a net_settings1=\"auto auto\" -a netboot_kernel=64 #{client}"
	output = self.run_command(command)
	return output
      end
      return "Client Already Defined"
    end

    def clientsettings(client)
      ## will get the status of client "client"
      command = "lsnim -l #{client}"
      output = self.run_command(command)
      regexp = /\s+(?'name'\S+)\s+=\s(?'value'.+)/
      hash_settings = output.scan(regexp).map { |x| {x[0].to_sym => x[1] }}
      return clientsettings
    end
    
    def nimcommand(jobtype,target,options = {})
      ## this will create a nim job of type "jobtype" on client "client" with arrayressources
      addtl_objects = ""
      switches = ""
      if options[:objects]
	options[:objects].each do |obj|
	addtl_objects << "-a #{obj}"
	end
      end
      if options[:force] == true
	switches << "-F "
      end
      command = "nim #{switches}-o #{jobtype} #{addtl_objects} #{target}"
      output = self.run_command(command)
      return output
    end
   
    def run_command(command)
      self.log.debug("command on #{self.name} => #{command}")
      return_val = String.new
      $nim_ssh.exec! command do |ch, stream, data|
        if stream == :stdout
          return_val << data.chomp
        end
      end
      return return_val
    end

    def lppsource
      #return a array of available lpp_sources along with their versions
      array_return = Array.new
      command = 'lsnim -t lpp_source'
      regexp_parse = /(?'resname'^\w+)/
      output = self.run_command(command).chomp
      array_return = output.scan(regexp_parse).flatten
      return array_return
    end
  
    def spots
      #return a array of available spots along with their versions
      array_return = Array.new
      command = 'lsnim -l -t spot'
      regexp_parse = /(?'resname'\w+):[^:]*oslevel_r\s+=\s(?'oslevel'\S+)[^:]/
      output = self.run_command(command).chomp
      output.scan(regexp_parse) do |spot|
	hash = { :spotname => spot[0],
	         :oslevel_r => spot[1] }
	array_return.insert(-1,hash)
	end
      return array_return
    end

    def mksysb
      #return a array of available mksysb along with their versions
      array_return = Array.new
      command = 'lsnim -l -t spot'
      regexp_parse = /(?'resname'\w+):[^:]*oslevel_r\s+=\s(?'oslevel'\S+)[^:]/
      output = self.run_command(command).chomp
      output.scan(regexp_parse) do |mksysb|
        hash = { :mksysbname => mksysb[0],
                 :oslevel_r => mksysb[1] }
        array_return.insert(-1,hash)
        end
      return array_return
    end
    
   def networks
     array_return = Array.new
     regexp = /(?'netname'\w+):[^:]*net_addr\s+=\s(?'netaddr'.+)\s+snm\s+=\s(?'netmask'.+)\s+routing1\s+=\s\w+\s(?'gateway'.+)[^:]/
     command = 'lsnim -l -t ent'
     output = self.run_command(command)
     output << "\n"
     output.scan(regexp).each do |net|
       hash = { :netname => net[0],
                :network => net[1],
                :netmask => net[2],
                :gateway => net[3] }
       array_return.insert(-1,hash)
     end
     return array_return
   end
  ## End of NIM Class
  end
end
