# The Frame class is used to define frame objects.
# Each frame object comes with it's own VIO servers Instances
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
require_relative 'error'

module PowerVMTools
  class Frame

    attr_accessor :name
    attr_reader :vioservers 
    attr_reader :lpars, :hmc, :debug

    def initialize(framename, objhmc, options = {})
      @name = framename 
      @hmc = objhmc
      @log = Logger.new(STDOUT)
      @log.level = Logger::INFO
      if @hmc.debug == true
	@debug = true
        @log.level = Logger::DEBUG
      end	
      @log.debug("New Frame instance #{framename}") 
      if not self.hmc.frameExists?(framename)
	@log.fatal("Frame #{framename} does not exists on this HMC")
	exit 1
      end
      getvioservers
    end

    private 
    # This method is used to populate the self.vioservers attribute with a array 
    # made of the VIO Servers Objects.
    def getvioservers
      begin 
        @log.debug("Getting VIOServers for #{self.name}") 
	retarray = Array.new
	command = "lssyscfg -r lpar -m #{@name} -F lpar_type,lpar_id,name | grep vioserver"
        output = self.hmc.run_command(command).chomp()
	if output =~ /^HSCL/
	  raise PowerVMTools::Error::CustomError, {:message => output, :command => command}
	end
        output.split("\n").each do |line|
	  params = line.split(',')
	  objvio = PowerVMTools::Vios.new(params[2], {:frame => self})
          retarray.insert(-1,objvio)
        end
        @vioservers = retarray
      rescue PowerVMTools::Error::CustomError => e
	e.handle
      end
    end
  
    public 

    # return the VIO Server object for vio server id 'id'
    def vioserver(id)
      @log.debug("Getting VIO object for vioid #{id}") 
      ## will return the vio server object 
      objvio = self.vioservers.select { |x| x.id == id }
      if objvio.length > 0
	return objvio[0]
      else
	return nil
      end
    end

    # Return a (bool) True/False statement if the lpar exists or not
    def lparexists?(lparname)
      @log.debug("Checking if lpar #{lparname} exists on #{self.name}") 
      getlpars
      if @lpars.select { |x| x == lparname }.length > 0
	return true
      else
	return false 
      end
    end

    # Populate the lpars attribute with a list of all defined lpar on this
    # frame.
    def getlpars
      @log.debug("Getting lpar list on #{self.name}") 
      @lpars = Array.new
      begin 
	command = "lssyscfg -r lpar -m #{@name} -F name"
        output = self.hmc.run_command(command).chomp()
	if output =~ /^HSCL/
	  raise PowerVMTools::Error::CustomError, {:message => output, :command => command}
	end
        output.split("\n").each do |entry|
          @lpars.push(entry)
        end
      return @lpars
      rescue PowerVMTools::Error::CustomError => e
	e.handle
      end
    end

    # return a array of all the network defined on this managed frame
    def networks
      @log.debug("Getting networks list on #{self.name}") 
      array_return = Array.new
      command = "lshwres --rsubtype vnetwork -r virtualio -m #{self.name}"
      output = self.hmc.run_command(command).chomp()
      regexp = /vnetwork=(?'vnetwork'\S+),is_tagged=(?'tagged'\d),vswitch=(?'vswitch'\S+),vlan_id=(?'vlanid'\d+)/
      output.scan(regexp).each do |entry|
        hash = { :vnetwork => entry[0],
	  	 :is_tagged => entry[1].to_i,
		 :vswitch => entry[2],
	  	 :vlan_id => entry[3].to_i}
	array_return.insert(-1,hash)
      end
      array_return
    end
  ## End of Frame Class
  end
end
