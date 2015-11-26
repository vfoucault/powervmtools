# This class is used to create VIO Objects.
# VIO Objects are only created from withing a frame object.
# This class extends the Lpar class.
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
  class Vios < Lpar
    attr_accessor :name,:id
    attr_reader :frame, :vadapters
    
    # This method initialize a new VIO Object.

    def initialize(name, options = {})
      @name = name
      super(name,options)
      @log = Logger.new(STDOUT)
      @log.level = Logger::INFO
      if options[:frame].debug == true
	@debug == true
        @log.level = Logger::DEBUG
      end	
      @log.debug("New VIOs instance #{name}") 
      getvadapters 
    end

    # Will populate the attribut hdisk_bible
    # with a Array of Hashes.
    # Array = [{ :name => "hdisk10",
    #            :sernum => "17B43",  
    #            :ldev => "0218",
    #            :pvid => "hdisk pvid or none"
    #            :vtd => "The VTD name if mapped". }]
    # This work so far only for Hitachi VSP Arrays,
    # But can easily implement other storage array
    def get_hdisk_bible
      if @hdisk_bible
        @log.debug("Getting hdisk bible on #{self.name}") 
	@hdisk_bible
      else
        @log.debug("Updating hdisk bible on #{self.name}") 
        command = "chkdev -verbose -field name identifier pvid vtd -fmt :"
        output = run_command(command)
	@hdisk_bible = Array.new
        regexp_devices = /^(\w+):\w+\s(\w{5})(\w{4}).{20}:(\w{4,16}):?0{0,16}:(\w+)?/ ### regexp that parse hitachi devices
        ref_devices = output.scan(regexp_devices)
        ref_devices.each do |entry|
          hash = { :name => entry[0],
                   :sernum => entry[1],
                   :ldev => entry[2],
                   :pvid => entry[3],
                   :vtd => entry[4]}
	  @hdisk_bible.push(hash)
        end
	@hdisk_bible
      end
    end	

    # Execute "command" on the VIO Server (via HMC SSH Connexion using viosvrcmd)
    def run_command(command)
      viocmd = "viosvrcmd -m #{self.frame.name} --id #{self.id} -c \"#{command}\""
      @log.debug("command on #{self.name} => #{command}")
      @log.debug("full hmc command => #{viocmd}")
      return_val = String.new
      $hmc_ssh.exec! viocmd do |ch, stream, data|
        if stream == :stdout
          return_val << data.chomp
        end
      end
      return return_val
    end
    
    # Fetch and return a array of hashes of the mappings for the specified vhost adapters	
    # Array = [ { "vtd" => "The vtd name",
    #             "lun" => "the vscsi lun (0x81,0x82...),
    #             "backingdevice" => "hdisk17",
    #             "pvid" => "the hdisk pvid if any or none",
    #             "sernum" => "The Storage array serial number",
    #             "devid" => "The Logical device ID",
    #             "size" => "hdisk size" } ]
    def mappings(vhost)
      @log.debug("Getting mappings for #{vhost} on #{self.name}")
      array_mapping = Array.new
      return array_mapping if vhost.nil?
      if not @hdisk_bible
	get_hdisk_bible
      end
      ### Will fetch all the mappings for lpar lparname
      command = "lsmap -vadapter #{vhost} -field 'Backing device' VTD LUN -fmt \":\""
      mapping = run_command(command)
      if mapping.length != 5
        mapping.split(":").each_slice(3) do |item| 
	  if item[0] =~ /^hdisk/
	    hdisk_entry = @hdisk_bible.select { |x| x[:name] == item[0]}[0]
	    size = run_command("lspv -size #{item[0]}").chomp()
            hash = { "vtd" => item[1],
                     "lun" => item[2][0,4],
                     "backingdevice" => item[0],
                     "pvid" => hdisk_entry[:pvid],
                     "sernum" => hdisk_entry[:sernum],
                     "devid" => hdisk_entry[:ldev],
                     "size" => size }
            array_mapping.insert(-1,hash)
	  end
	end
      end
      return array_mapping
    end 

    # Execute the cfgdev command on this vio.
    # the optional "dev" argument is used to specified the root device 
    # to initiate the cfgdev from.
    def cfgdev(*dev)
      ## will run the cfgdev command on the vios
      @log.debug("Running 'cfgdev' on #{self.name}")
      optargs = ""
      optargs = "-dev #{dev[0]}" if not dev.nil?
      command = "cfgdev #{optargs}"
      output = self.run_command(command)
      return output
    end

    # return a Array of Vlans available on the VIOs
    def networks
      @log.debug("Getting networks list on #{self.name}")
      command = "lshwres -r virtualio --rsubtype eth  -m C1IbmP770-telox --level lpar -F lpar_name,addl_vlan_ids --filter lpar_names=#{self.name}"
      output = self.frame.hmc.run_command(command)
      regexp = /(?<=,|")(\d+)/
      vlans = output.scan(regexp).flatten.map { |x| x.to_i}.sort
      vlans
    end

    private  

    # Used to populate the vadapters attribute with a array of hashes
    # of the vadpater id and it's associated device name
    # Array = [{ :said => 15,
    #            :dev => "vhost10"}]
    def getvadapters(*optargs)
      @log.debug("Getting vadapters list on #{self.name}")
      begin 
        if not optargs[0].nil?
          watchdog = optargs[0]
          @log.debug("Running getvadapter with watchdog = #{watchdog}")
        else 
          watchdog = 0
        end
        if watchdog == 2
          @log.debug("Two much watchdogs ! ending endless loop getvadapters")
          raise PowerVMTools::Error::CustomError, {:message => "Two much watchdogs ! ending endless loop getvadapters"}
        end
        arrayret = Array.new
         command = "lsdev -slots"
         output = run_command(command).chomp()
         regexp = /-C(\d+)\s+.+\b(\w+)/
         output.scan(regexp).each do |entry|
           if entry[1] == "Unknown"
	     raise PowerVMTools::Error::CustomError, {:message => "Some Unknown devices !" }
           end
           arrayret.push({ :said => entry[0].to_i,:dev => entry[1]})
         end
         @vadapters = arrayret
         @vadapters
      rescue PowerVMTools::Error::CustomError => e 
	if e.message == "Some Unknown devices !"
	  cfgdev("vio0")
          getvadapters(watchdog)
	  e.handle
	 end 
      end
    end
 
    public 

    # Will return the device name for the specifed adap_id
    # uses the attribute vadapters 
    def getvadaptername(adap_id)
      ## return the vhost adapter name (eg: vhost5) from the VIOS
      vadaptername = nil
      if not @vadpaters
	getvadapters
      end
      entry = @vadapters.select { |x| x[:said] == adap_id }
      vadaptername = entry[0][:dev] if entry.length > 0
      @log.debug("Getting vadapter device name for #{adap_id}=>#{vadaptername} on #{self.name}")
      return vadaptername
    end

    # Will return a Hash made of the vfcmap for the specified vfchost
    # Hash = {"status" => status,
    #         "fcname" => fcname,
    #         "physloc" => physloc,
    #         "portstatus" => portsli,
    #         "flags" => flags,
    #         "clntfcname" => clntfcname}
    def getvfcmap(vfchost)
      @log.debug("Getting vfc mapping for #{vfchost} on #{self.name}")
      hash_mapping = Hash.new
      command = "lsmap -vadapter #{vfchost} -npiv -fmt ':'"
      mapping = run_command(command)
      if not mapping.nil?
        fcmap = mapping.split(":")
        ## vfchost0:U9117.MMD.XXXXXXX-V1-C7:15:lpar1:AIX:LOGGED_IN:fcs0:U2C4E.001.DBY0000-P2-C4-T1:1:a:fcs0:U9117.MMD.XXXXXXX-V15-C30
        status =  fcmap[5]
        fcname =  fcmap[6]
        physloc = fcmap[7]
        portsli = fcmap[8]
        flags =   fcmap[9]
        clntfcname = fcmap[10]
        hash_mapping = {"status" => status,
                        "fcname" => fcname,
                        "physloc" => physloc,
                        "portstatus" => portsli,
                        "flags" => flags,
                        "clntfcname" => clntfcname}
      end
      return hash_mapping
    end

    # Will execute the rmdev command on this vio for the specified devname
    def rmdev(devname)
      @log.debug("Removing device #{devname} on #{self.name}")
      command = "rmdev -dev #{devname}"
      output = self.run_command(command)
    end

    # Will remove the vscsi mapping for the specified vtdname
    def removemapping(vtdname)
      begin
        @log.debug("Removing mapping #{vtdname} on #{self.name}")
	command = "rmvdev -vtd #{vtdname}"
	output = self.run_command(command)
	return output
      end 
    end 

    # Will create the vscsi mapping for the specified devices with options : 
    # device => the device for create the mapping for
    # vadapter => the vadpater to create the mapping on
    # options : { :force => True/False,
    #             :vtdname => the vtdname}
    def createmapping(device,vadapter,options = {})
      begin
        if options[:vtdname] 
          vtdname = "-dev #{options[:vtdname]}"
        end
        if options[:force] == true
          force = "-f"
        end
        @log.debug("Creating mapping #{device}/#{vadapter} on #{self.name}")
        command = "mkvdev #{force} -vdev #{device} -vadapter #{vadapter} #{vtdname}"
	output = self.run_command(command)
      rescue PowerVMTools::Error::CustomError => e
	e.handle
      end
    end

    # Will create a VFC map between the specified vfcdev & fc dev
    def mkfcmap(vfcname,fcname)
      @log.debug("Creating vfc mapping #{vfcname}/#{fcname} on #{self.name}")
      command = "vfcmap -vadapter #{vfcname} -fcp #{fcname}" 
      output = self.run_command(command)
    end
  ## End of Lpar Class
  end
end

