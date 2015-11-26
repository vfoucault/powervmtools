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
module PowerVMTools
  module Common

    def self.testlink(host,user,pass,options = {})
      begin
	port = options[:port] || 22
	command = options[:cmd] || "who"
        Net::SSH.start( host, user, {:password => pass, :port => port}) do |ssh|
          dummy_result = ssh.exec!(command)
        end
	return true
      rescue Timeout::Error
        puts "  Timed out connecting to #{options[:name]}"
      rescue Errno::EAFNOSUPPORT
        puts "  SSH Link: #{options[:name]} unreachable - Address family not supported by protocol"
      rescue Errno::EHOSTUNREACH
        puts "  SSH Link: #{options[:name]} unreachable"
      rescue Errno::ECONNREFUSED
        puts "  SSH Link: #{options[:name]} Connection refused for #{options[:user]}"
      rescue Net::SSH::AuthenticationFailed
        puts "  SSH Link: #{options[:name]} authentification failed for #{options[:user]}"
      rescue Exception => e
	puts "main:#{e}"
      end
    end


    def self.parse_profile(data)
      #
      #parse a string composed of key=value separated by commas
      #it returns a hash of k,v
      #
      hash_of_keys = Hash.new
      ### Frist of all, let's clean and remove all the \n inside the string :
      array = data.gsub!(",","\n").split
      setroot = 0
      array.each_index do |index|
        setroot = index if array[index] =~ /=/
        array[setroot] << ",#{array[index]}" if not array[index] =~ /=/
        array[index] = "" if not array[index] =~ /=/
      end.reject { |s| s.strip.empty? || s.nil?}.map { |s| key,value = s.split("="); value = "" if value.nil?;  hash_of_keys[key.delete("\\").delete('"').to_sym] = value.delete("\\").delete('"') }
      ### little extra, let's update the virtual_fc_adapters to replace the comma between the two wwn by a / it will be easier to handle in the futur
      if not hash_of_keys[:virtual_fc_adapters].nil? and hash_of_keys[:virtual_fc_adapters].match(/[[:xdigit:]]{16},[[:xdigit:]]{16}/)
	hash_of_keys[:virtual_fc_adapters].gsub!(/([[:xdigit:]]{16}),([[:xdigit:]]{16})/,'\1' + "/" + '\2')
      end
      return hash_of_keys
    end

    def self.parse_virtual_line(line)
      ### this function will take a profile virtual line as arg 
      ## "20/client/1/viosrv1/2/0,21/client/2/viosrv1/7/0,22/client/1/viosrv2/3/0,23/client/2/viosrv2/8/0"
      ## and will return an array of hashes : 
      ## {:clientadapterid => 20, 
      ##  :serveradapterid => 2, 
      ##  :vioserverid =>1, 
      ##  :vdevname => vhost1,
      ##  :mappings => { "to be defined" }}
      return_array = Array.new
      line.split(",").each do |vscsi|
        array_info = vscsi.split("/") ## spliting into a array the vscsi line
        clientadapterid = array_info[0].to_i
        serveradapterid = array_info[4].to_i
        vioserverid = array_info[2].to_i
        return_array.push({:clientadapterid => clientadapterid, :serveradapterid => serveradapterid, :vioserverid => vioserverid })
      end
      return return_array
    end

    def self.parse_virtualfc_line(line)
      ### this function will take a profile virtual fc line as arg 
      ## "30/client/1/viosrv1/7/c050760848060000/c050760848060001/0,31/client/2/viosrv2/9/c050760848060002/c050760848060003/0"
      ## and will return an array of hashes : 
      ## {:clientadapterid => 30, 
      ##  :serveradapterid => 7, 
      ##  :vioserverid =>1, 
      ##  :wwn1 => "c050760848060000", 
      ##  :wwn2 => "c050760848060001"
      ## }
      return_array = Array.new
      line.split(",").each do |vfc|
        array_info = vfc.split("/") ## spliting into a array the vfc line
        clientadapterid = array_info[0].to_i
        serveradapterid = array_info[4].to_i
        vioserverid = array_info[2].to_i
        return_array.push({:clientadapterid => clientadapterid, :serveradapterid => serveradapterid, :vioserverid => vioserverid, :wwn1 => array_info[5], :wwn2 => array_info[6]})
      end
      return return_array
    end
  ## End of Common module
  end
end
