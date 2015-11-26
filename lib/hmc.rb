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
  $hmc_ssh = "empty"
  # The HMC class is used to define HMC objects.
  #
  class HMC

    # Attributes : 
    # @name => the HMC name
    # @user => the HMC username
    # @passwd => the HMC user's Password.
    # @port =>  the HMC SSH port
    attr_accessor :name, :user, :passwd, :port
    # @frames => All this HMC Frames
    # @log => This HMC logger
    # @debug => Hold the debug status
    attr_reader :frames, :log, :debug

    # The new method.
    # options are : 
    # 
    # * :user : HMC username to use. Must have the Rights to launch VIO Commands
    # * :passwd : the associated password
    # * :port : the SSH Port if not default
    # * :debug : True/False (bool)
    def initialize(name, options = {})
      @hmcsettings = Hash.new
      @name = name
      @log = Logger.new(STDOUT)
      @log.level = Logger::INFO
      if options[:debug] == true
	@debug = true
        @log.level = Logger::DEBUG
      end	
      @log.debug("New HMC instance #{name}") 
      setuphmc(name,options) 
    end

    private 
    # Setup the HMC connextion. 
    # called by the new constructor only.
    def setuphmc(name, options = {})
      @hmcsettings = { :name => name,
		       :user => options[:user] || "hscroot",
		       :passwd => options[:passwd] || nil,
		       :port => options[:port] || 22
		       }
      PowerVMTools::Common.testlink(@hmcsettings[:name],@hmcsettings[:user],@hmcsettings[:passwd],{:port => @hmcsettings[:port],:cmd => "lshmc -V"})
      $hmc_ssh = Net::SSH.start( @hmcsettings[:name],@hmcsettings[:user], {:password => @hmcsettings[:passwd],:port => @hmcsettings[:port]})
      @frames = getframes()
    end
 
    public 
    
    # Check if frame 'framename' exists on this HMC
    # return a (bool) True/False
    def frameExists?(framename)
      isFrameExists = @frames.select { |x| x[:name] == framename }.length
      if isFrameExists == 1
	@log.debug("frameExists => #{framename} | true")
	return true
      else
	@log.debug("frameExists => #{framename} | false")
        return false
      end
    end
    
    # Run a hmc command and returns the output
    def run_command(command)
      self.log.debug("command on #{self.name} => #{command}")
      return_val = String.new
      $hmc_ssh.exec! command do |ch, stream, data|
        if stream == :stdout
          return_val << data.chomp
        end
      end
      if return_val =~ /The command entered is either missing a required parameter or a parameter value is invalid/
	raise PowerVMTools::Error::CustomError, { :command => command, :message => return_val }
      end
      return return_val
    end
  
    # return a Array of frames filtered by status
    def framesbystatus(status)
      array_return = Array.new
      if @frames.nil?
        puts " HMC #{@name} No managed systems managed by this HMC"
      end
      @frames.map{ |x| if x[:state] == status;  array_return.insert(-1, x[:name]); end }
      return array_return
    end

    # return a Array of frames along with their configuration (lssyscfg)
    def getframes()
      array_of_frames = Array.new
      array_of_threads = Array.new
      command = "lssyscfg -r sys"
      output = self.run_command(command).chomp()
      output.split("\n").each do |entry|
        array_of_threads << Thread.new {
          settings = PowerVMTools::Common::parse_profile(entry)
          array_of_frames.insert(-1,settings)
        }
        array_of_threads.each { |thread| thread.join }
      end
      @frames = array_of_frames
      return @frames
    end

  ## End of HMC Class
  end
end
