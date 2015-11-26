# The Lpar Class is used to create lpar objects.
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
  class Lpar
    attr_accessor :name
    attr_reader :id,:frame,:profile,:profiles,:createsettings,:config

    # the new method used to define lpar objects
    # options : 
    # * :frame : the frame object which holds/will holds the lpar
    # * :debug : (bool) True/False : Enable the debug  output
    def initialize(name,options = {})
      @name = name
      @log = Logger.new(STDOUT)
      @log.level = Logger::INFO
      if options[:frame]
	@log.debug("Settings frame #{options[:frame].name} for #{self.name}")
	setframe(options[:frame])
      end
      if options[:debug] == true
	@debug = true
	@log.level = Logger::DEBUG
      end
      @log.debug("New Lpar instance #{self.name}") 
    end

    # Set the frame objframe to this object.
    # Can be use to update a lpar object at creation time (self.create())
    def setframe(objframe)
      begin
        @frame = objframe
        if @frame.debug == true
          @debug = true
          @log.level = Logger::DEBUG
        end	
        if objframe.lparexists?(self.name)
	  @log.debug("Updating Objects #{self.name} settings")
          @config = getlparconfig
          @id = @config[:lpar_id].to_i
          @profiles = getlparprofiles
          default_profile = self.config[:curr_profile]
	  if default_profile == ""
	    default_profile = self.config[:default_profile]
	  end
          @profile = @profiles.select { |x| x[:name] == default_profile }.flatten[0] 
	end
      rescue PowerVMTools::Error::CustomError => e
	e.handle
	exit 1
      end
    end

    # Return the Lpar configuration (not profile) as a hash of settings
    def getlparconfig
      begin
        @log.debug("Getting LPAR configuration for #{self.name}") 
	command = "lssyscfg -r lpar -m #{@frame.name} --filter \"lpar_names=#{self.name}\""
	output = self.frame.hmc.run_command(command).chomp()
	config = PowerVMTools::Common.parse_profile(output)
	return config
      end
    end

    ## will get all profiles for the lpar, returning an Array of : 
    ## Array = [ {profiledata1},{profiledata2}]
    def getlparprofiles
      begin
        @log.debug("Getting all profiles for #{self.name}") 
	array_return = Array.new
	command = "lssyscfg -r prof -m #{@frame.name} --filter \"lpar_names=#{self.name}\""
        output = self.frame.hmc.run_command(command).chomp()
	output.each_line do |line|
	  array_return.push(PowerVMTools::Common.parse_profile(line))
	end
	return array_return
      end
    end

    # return a list of vscsi mappings for this lpar.
    def getmappings
      @log.debug("Getting all vscsi mappings for #{self.name}") 
      ## will fetch mappings for lpar objlpar
      vscsiline = self.profile[:virtual_scsi_adapters] 
      if vscsiline == "none" or vscsiline == nil
	@log.debug("No vscsi mappings for #{self.name}")
        return nil
      end
      parsedvscsiline = PowerVMTools::Common.parse_virtual_line(vscsiline)
      parsedvscsiline.each_index do |index|
	vioid = parsedvscsiline[index][:vioserverid]
	said = parsedvscsiline[index][:serveradapterid]
	objvio =  self.frame.vioservers.select { |x| x.id == vioid}.flatten[0]
	devname = objvio.getvadaptername(said) 
	parsedvscsiline[index][:devname] = devname
	mappings = objvio.mappings(devname)
	parsedvscsiline[index][:mappings] = mappings
      end
      return parsedvscsiline
    end

    # return a list of vfc mappings for this lpar
    def getvfcmappings
      @log.debug("Getting all vfc mappings for #{self.name}") 
      vfcline = self.profile[:virtual_fc_adapters] 
      if vfcline == "none" or vfcline == nil
	@log.debug("No vfc mappings for #{self.name}")
        return nil
      end
      parsedvfcline = PowerVMTools::Common.parse_virtualfc_line(vfcline)
      parsedvfcline.each_index do |index|
	vioid = parsedvfcline[index][:vioserverid]
	said = parsedvfcline[index][:serveradapterid]
	objvio = self.frame.vioservers.select { |x| x.id == vioid}.flatten[0]
	devname = objvio.getvadaptername(said)
	mappings = objvio.getvfcmap(devname)
	parsedvfcline[index][:devname] = devname
	parsedvfcline[index][:fcmap] = mappings
      end
      return parsedvfcline
    end

    # Set the settings for the lpar creation.
    def setsettings(options = {})
      @log.debug("Setting creation settings for #{self.name}") 
      ### register settings 
      @createsettings = options
    end
    
    # will initiate a net_boot along with the specified options : 
    # { :ip => '192.168.10.16',
    #   :netmask => '255.255.255.0',
    #   :gateway => '192.168.10.1',
    #   :server => '192.168.11.3' }
    def net_boot(options = {})
      begin
	## Check options : 
	if options[:ip].nil? or options[:netmask].nil? or options[:gateway].nil? or options[:server].nil?
	  raise PowerVMTools::Error::CustomError, {:message => "Some options aren't set. Exit 1." }
	end	
	command = "lpar_netboot -f -T off -t ent -s auto -d auto -D -K #{options[:netmask]} -G #{options[:gateway]} -S #{options[:server]} -C #{options[:ip]} #{self.name} #{self.profilename} #{self.frame.name}"
	self.hmc.run_command(command)
      rescue PowerVMTools::Error::CustomError => e
          e.handle
          exit 1
      end
    end

    # Will initate a Power Operation for this lpar with the specified options : 
    # { :action => "poweron" | "poweroff",
    #   :restart => Bool. True | False,
    #   :immed => Bool. True | False,
    #   :os => Bool. True | False}
    def power(options = {})
      ## will power on/off system or not and immed
      begin
        command = "chsysstate -m #{self.frame.name} --id #{self.id}" 
        case options[:action] 
          when "poweroff"
	    cstate = getstate()
	    if cstate == "Not Activated"
	      raise PowerVMTools::Error::PowerStateError, {:state => "Running | Open Firmware", :cstate => cstate, :object => self.name }
	    end 
            if options[:os] == true 
              command << " -o osshutdown -r lpar"	
            else
              command << " -o shutdown -r lpar"	
            end
            if options[:restart] == true
              command << " --restart"
            end 
            if options[:immed] == true
              command << " --immed"
            end 
          when "poweron"
	    cstate = getstate()
	    if not cstate == "Not Activated"
	      raise PowerVMTools::Error::PowerStateError, {:state => "Not Activated", :cstate => cstate, :object => self.name }
	    end 
            command << " -o on -r lpar"
	    if self.config[:curr_profile] == ""
	      command << " -f #{self.config[:default_profile]}"
	    end
        end
        @log.debug("Changing power status for #{self.name}") 
        output = self.frame.hmc.run_command(command)
	if output =~ /An invalid parameter value was entered/ or output =~ /HSCL/
	  raise PowerVMTools::Error::CustomError, {:message => output, :command => command}
	end
      rescue PowerVMTools::Error::PowerStateError => e
	e.handle
	exit 1
      rescue PowerVMTools::Error::CustomError => e
	e.handle
	exit 1
      end
    end

 
    # return the lpar status.
    def getstate()
      @log.debug("Getting status for #{self.name}") 
      command = "lssyscfg -r lpar -m #{self.frame.name} -F state --filter lpar_names=#{self.name}"
      output = self.frame.hmc.run_command(command).chomp()
      output
    end
   
    # Save the running profile to the current profile.
    def save_profile()
      @log.debug("Saving running profile for #{self.name}") 
      command = "mksyscfg -r prof -m #{self.frame.name} -o save --id #{self.id} -n $(lssyscfg -r lpar -m #{self.frame.name} --filter \\\"lpar_ids=#{self.id}\\\" -F curr_profile) --force"
      output = self.frame.hmc.run_command(command)
    end

    # Will create and return a Hash of Hashes of the vadapters names on the vio server
    def getvioadaptersnames()
      ## we will try to get the vio server adapter names for our client devices
      @log.debug("Getting Adapter names on VIO for #{self.name}") 
      lines = ""
      if self.profile[:virtual_scsi_adapters]
        lines << self.profile[:virtual_scsi_adapters] + ","
      end
      if self.profile[:virtual_fc_adapters]
        lines << self.profile[:virtual_fc_adapters] + ","
      end
      hash = Hash.new
      lines.split(",").each do |line| 
        device = line.split("/")
        objvio = self.frame.vioserver(device[2].to_i)
        hash[objvio.id] = Array.new if not hash.has_key?(objvio.id)
        hash[objvio.id].push([device[4].to_i,objvio.getvadaptername(device[4].to_i)])
      end
      hash
    end

    # Delete this lpar, with options : 
    # { :test => (bool) True | False }
    def deletelpar(options = {})
      @log.debug("Deleting Partition #{self.name}") 
      if options[:test] == true
	puts "This is a test only no create will occur"
      end
      begin
	cstate = getstate
        if not cstate == "Not Activated"
	  raise PowerVMTools::Error::PowerStateError, {:state => "Not Activated", :cstate => cstate, :object => self.name }
	end
	updatedvios = Array.new
	mappings = getmappings.concat(getvfcmappings)
	mappings.each do |vadapter|
	  objvio = self.frame.vioserver(vadapter[:vioserverid])
	  if not vadapter[:mappings].nil? and vadapter[:mappings].length > 0	
	    vadapter[:mappings].each do |map| 
	      objvio.removemapping(map["vtd"])
	    end
	  end
          objvio.rmdev(vadapter[:devname])
	  subtype = nil
	  case vadapter[:devname]
	  when /vhost/
	    subtype = "scsi"
	  when /vfchost/
	    subtype = "fc"
	  end
	  objvio.dlpar("remove",{:type => "virtualio", :subtype => subtype, :said => vadapter[:serveradapterid]})
	  updatedvios.insert(objvio.id)
	end
 	updatedvios.uniq { |x| objvio = self.frame.vioserver(x); x.save_profile; x.cfgdev("vio0")}	
	command = "rmsyscfg -r lpar -m #{self.frame.name} -n #{self.name}"
	output = self.frame.hmc.run_command(command)
	## update remaining objects
	@log.debug("Deleted partition #{self.name}")
	self.frame.getlpars
	@id = nil
	@frame = nil
	@profile = nil
	@profiles = nil
	@createsettings = nil
	@config = nil
      rescue PowerVMTools::Error::PowerStateError => e
	e.handle
	exit 1
      rescue PowerVMTools::Error::CustomError => e
	e.handle
	exit 1
      end
    end

    # Will create a lpar with the following options.
    # Must specify settings with self.setsettings() before.
    # { :test => (bool) True | False
    #   :do_roll_back_if_failure => (bool) True | False }
    # It's important to note that is there is some vscsi devices,
    # the corresponding adapters will be hot added to the correspondings
    # Vio Servers via DLPAR.
    def create(options = {})
      @log.debug("Creating partition #{self.name}") 
      begin
        if options[:test] == true
          puts "This is a test only no create will occur"
        end
        settings = self.createsettings
        profilestring = "\"name=#{self.name},profile_name=#{settings[:profile_name]},lpar_env=aixlinux,min_mem=#{settings[:mem][:min]},desired_mem=#{settings[:mem][:des]},max_mem=#{settings[:mem][:max]},mem_expansion=#{settings[:ame]},proc_mode=#{settings[:procmode]},min_procs=#{settings[:cpu][:minvp]},desired_procs=#{settings[:cpu][:desvp]},max_procs=#{settings[:cpu][:maxvp]},min_proc_units=#{settings[:cpu][:minec]},desired_proc_units=#{settings[:cpu][:desec]},max_proc_units=#{settings[:cpu][:maxec]},sharing_mode=#{settings[:sharing_mode]},uncap_weight=#{settings[:uncap_weight]},boot_mode=norm,max_virtual_slots=#{settings[:max_virtual_slots]},\\\"virtual_eth_adapters=#{settings[:virtual_eth_adapters]}\\\",\\\"virtual_scsi_adapters=#{settings[:virtual_scsi_adapters]}\\\",\\\"virtual_fc_adapters=#{settings[:virtual_fc_adapters]}\\\"\""
        command = "mksyscfg -m #{self.frame.name} -r lpar -i #{profilestring}"
        if not options[:test] == true
          output = self.frame.hmc.run_command(command)
          if output =~ /The format of the configuration data is invalid./ or output =~ /of the memory region size for the managed system./
            raise PowerVMTools::Error::CustomError, {:message => output, :command => command, :action => "Create"} 
          end
	  ### do vios
	  updatedvios = Array.new
	  if not settings[:virtual_scsi_adapters].nil?
	    settings[:virtual_scsi_adapters].split(',').each do |entry|
	      vscsi = entry.split("/")
	      objvio =  self.frame.vioserver(vscsi[2].to_i)
	      updatedvios.push(objvio.id)
	      objvio.dlpar("add",{:type => "virtualio",
				  :subtype => "scsi", 
				  :said => vscsi[4],
				  :adapter_type => "server",
				  :remote_lpar_name => self.name,
				  :remote_slot_num => vscsi[0] })
	    end
	  end
	  if not settings[:virtual_fc_adapters].nil?
	    settings[:virtual_fc_adapters].split(',').each do |entry|
	      vfc = entry.split("/")
	      objvio =  self.frame.vioserver(vfc[2].to_i)
	      updatedvios.push(objvio.id)
	      objvio.dlpar("add",{:type => "virtualio",
				  :subtype => "fc", 
				  :said => vfc[4],
				  :adapter_type => "server",
				  :remote_lpar_name => self.name,
				  :remote_slot_num => vfc[0] })
	    end
	  end
	  updatedvios.uniq.each { |vios| obj = self.frame.vioserver(vios); obj.save_profile(); obj.cfgdev("vio0")}
	  ## forceing the setframe to update the current object to get the lpar ID
	  setframe(self.frame)
 	  ## Power Cycle the partition to activate the default profile
	  self.power({:action => "poweron" })
	  ## loop to get statue
	  cstate = getstate()
	  counter = 0
	  while cstate == "Not Activated"
	    @log.debug("Waiting for lpar #{self.name} to start")
	    cstate = getstate()
	    sleep 1
	    counter += 1
	    raise PowerVMTools::Error::CustomError, {:message => "Timeout waiting for lpar to come up", :action => "Startup" } if counter == 60
	  end
	  self.power({:action => "poweroff", :immed => true })
	  ## forceing the setframe to update the current object to get profile & profiles setted
	  setframe(self.frame)
        else
          @log.info("Command not executed => #{command}")
        end
      rescue PowerVMTools::Error::CustomError => e
        e.handle
	if not options[:do_roll_back_if_failure].nil?
	  # if do_roll_back_if_failure is nil, we've asked to not roll back operation after a failure.
 	  # here we want it
	  self.deletelpar()  
	end    
	exit 1
      end
    end
  
    # Initiate a DLPAR operation on this lpar Object.
    # the options are used to defined the settings : 
    # 
    # { :type => "adapter type : virtualio",
    #   :subtype => "vscsi...",
    #   :said => "Server Adapter ID",
    #   :adapter_type => "client|server",
    #   :remote_lpar_name => "othersidelparname",
    #   :remote_slot_num => "othersideslotnum"
    # }
    # 
    def dlpar(action,options = {})
      begin
	command = ""
	case action
	when "add"
	  command = "chhwres -m #{self.frame.name} -r #{options[:type]} -o a --id #{self.id} --rsubtype #{options[:subtype]} -s #{options[:said]} -a \"adapter_type=#{options[:adapter_type]},remote_lpar_name=#{options[:remote_lpar_name]},remote_slot_num=#{options[:remote_slot_num]}\""
          @log.debug("Hotadding device type #{options[:subtype]} to partition #{self.name}") 
	when "remove"
	  command = "chhwres -m #{self.frame.name} -r #{options[:type]} -o r --id #{self.id} --rsubtype #{options[:subtype]} -s #{options[:said]}"
          @log.debug("Hotremoving device type #{options[:subtype]} from partition #{self.name}") 
	else 
	  raise PowerVMTools::Error::CustomError, {:message => "Error with dlpar type : must be add or remove" }
	end
	output = self.frame.hmc.run_command(command)
        if output =~ /HSCL294D Dynamic remove of virtual I\/O resources failed/ or output =~ /The format of the configuration data is invalid./
	  raise PowerVMTools::Error::CustomError, {:message => output, :command => command }
	end
      rescue PowerVMTools::Error::CustomError => e
	e.handle
	#exit 1
      end
    end

  ## End of Lpar Class
  end
end

