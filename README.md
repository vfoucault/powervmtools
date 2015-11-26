# powervmtools

> Ruby library used to work with **IBM Power Hypervisor.**
> Tested on HMC v7r7.9 and VIOServer 2.2.3.4

## Build & Install :
```bash 
$ gem build powervmtools.gemspec
$ gem install powervmtools-version.gem
```
## Usage example :
(more examples at the end)

> Get a lpar configuration (not profile!)

```ruby
require 'powervmtools'
require 'pp'
myhmc = PowerVMTools::HMC.new('192.168.1.10',{ :user => 'hscroot',  :passwd => 'abc123'})
myframe = PowerVMTools::Frame.new('Frame1',myhmc)
mylpar = PowerVMTools::Lpar.new('Lpar1',{:frame => myframe })
pp mylpar.getlparconfig
```
Will output : 
```bash
{:name=>"Lpar1",
 :lpar_id=>"3",
 :lpar_env=>"aixlinux",
 :state=>"Not,Activated",
 :resource_config=>"1",
 :os_version=>"Unknown",
 :logical_serial_num=>"123X489",
 :default_profile=>"default",
 :curr_profile=>"default",
 :work_group_id=>"none",
 :shared_proc_pool_util_auth=>"0",
 :allow_perf_collection=>"0",
 :power_ctrl_lpar_ids=>"none",
 :boot_mode=>"norm",
 :lpar_keylock=>"norm",
 :auto_start=>"0",
 :redundant_err_path_reporting=>"0",
 :rmc_state=>"inactive",
 :rmc_ipaddr=>"",
 :time_ref=>"0",
 :lpar_avail_priority=>"127",
 :desired_lpar_proc_compat_mode=>"default",
 :curr_lpar_proc_compat_mode=>"POWER7",
 :suspend_capable=>"0",
 :remote_restart_capable=>"0",
 :sync_curr_profile=>"0",
 :affinity_group_id=>"none",
 :vtpm_enabled=>"0"}
```

> Get a lpar Disk mappings (vscsi) 

```ruby
require 'powervmtools'
require 'pp'
myhmc = PowerVMTools::HMC.new('192.168.1.10',{ :user => 'hscroot',  :passwd => 'abc123'})
myframe = PowerVMTools::Frame.new('Frame1',myhmc)
mylpar = PowerVMTools::Lpar.new('Lpar1',{:frame => myframe })
pp mylpar.getmappings
```
Will output : 
```bash
[{:clientadapterid=>20,
  :serveradapterid=>10,
  :vioserverid=>1,
  :devname=>"vhost0",
  :mappings=>
   [{"vtd"=>"vtdisk1",
     "lun"=>"0x81",
     "backingdevice"=>"hdisk72",
     "pvid"=>"00c9c37775dc3f63",
     "sernum"=>"17DE9",
     "devid"=>"02E4",
     "size"=>"65536"},
    {"vtd"=>"vtdisk2",
     "lun"=>"0x82",
     "backingdevice"=>"hdisk73",
     "pvid"=>"none",
     "sernum"=>"17DE9",
     "devid"=>"02E5",
     "size"=>"32768"}]},
...

```

## Classes : 

### HMC :

```ruby
myhmc = PowerVMTools::HMC.new('192.168.1.120',{ :user => 'hscroot', :passwd => 'abc123'})
```
This will create a HMC object.
Options : 

- ```:user``` : HMC username to use. Must have the Rights to launch VIO Commands
- ```:passwd``` : the associated password
- ```:port``` : the SSH Port if not default
- ```:debug``` : True/False (bool)

Methods :

* ```frameExists?(framename)``` :  Return true if 'framename' exists.
* ```run_command(command)``` :  Run 'command' on hmc and return the result.
* ```framesbystatus(status)``` : Get a list of frames by status (Operating...)
* ```getframes``` : Get a list for frames  managed by this hmc along with theire configuration (lssyscfg)

### Frame :

```ruby 
myframe = PowerVMTools::Frame.new('p770',hmc_object)
```
This will create the Frame Object

Methods : 

* ```vioserver(id)``` :  Will return the VIO Server Object for vioserver "id" (See VIO Class)
* ```lparexists?(lparname)``` : Return True if lpar "lparname" exits.
* ```getlpars```: Get a list of lpars hosted on this Frame.
* ```networks```: Get a list all the Vlans managed on this frame

### LPAR: 

```ruby 
mylpar = PowerVMTools::Lpar.new('lpar1', { :frame => obj_frame })
```
This will create the Lpar object. If Lpar already exists, specify the frame object while creating the lpar. If not, do not specify the option as we will specify if for the creation process.

Methods : 

* ```setframe(obj_frame)``` : Set the Frame for the Lpar object
* ```getlparconfig``` : Get all the Lpar Settings and return it as a hash
* ```getlparprofiles``` : Get all the Lpar profiles and return it as a Array of Hashes
* ```getmapping``` : Get all the vscsi mappings for this lpar object (Private)
* ```getvfcmappings``` :  Get all the vfc mappings for this lpar object (Private) 
* ```setsettings({})```: Set all the lpar creation settings.
  an option Hash is provided as the creations options.
* ```power({})```  : Power ON/OFF the lpar following 'options' 
  -- ```:action``` : poweroff/poweron
  -- ```:os``` : (bool.) True or False. Initiate a proper OS Shutdown
  -- ```:restart``` : (bool.) True or False. Initiate a machine restart
  -- ```:immed``` : (bool.) True or False. Initiate operations immediately (shutdown & restart)
*  ```getstate```  :  Get the Lpar state (lssyscfg)
*  ```save_profile```  :  Save the Running Lpar profile to the current profile
*  ```getstate```  :  Get the Lpar state (lssyscfg)
* ```getvioadaptersnames```: Get the VIO server adapter name for our client devices
* ```deletelpar({})```: Delete the Current Lpar
  -- ```:test```: (bool.) True or False
* ```create({})```: Create the Lpar with the specified settings (```setsettings({})```)
  -- ```:test```:  (bool.) True or False
* ```dlpar(action,{})```: Run a Dlpar operation.
  -- ```action```: add / remove
  -- ```:type``` : adapter type : virtualio"
  -- ```:subtype```: vscsi...
  -- ```:said``` : "Server Adapter ID"
  -- ```:adapter_type``` : "client|server"
  -- ```:remote_lpar_name``` : "otherside lpar name"
  -- ```:remote_slot_num``` : "otherside slot num"

### VIO :

This class is only initialized within a Frame Object.
This class extends the LPAR Class.

Methods (on a Frame's VIO object) :  myframe.vioservers[0] is an array of all the VIO Servers

* ```get_hdisk_bible```:Will update the local hdisk list with all the devices informations.
This Works only for Hitachi VSP Devices, as I do not have access so far to any other Storage Array.
* ```run_command(command)```: Run and return the output of the viossvrcmd for this vio server
* ```mappings(vhost)```Will return list of all the VTD mappings for this vhost (eg: vhost15)
* ```cfgdev(*dev)```:Will run the cfgdev command. 
the optional Argument is to specify the device, (eg: vio0), usefull to speedup DLPARs operations if needed.
* ```networks``` : Get a list of all the vlans served by this VIO server
* ```getvadapters``` : Will return a list of all the vadapters on this VIO, with the server adapters id and it's associated device name
* ```getvadaptername(adap_id)``` : Will return the adapter name for this server adapter id
* ```getvfcmap(vfchost)``` : Will return the VFC mapping for this vfchost
* ```rmdev(devname)``` Will remove the device "devname" from this VIO. This Device must not be in use.
* ```removemapping(vtdname)```: Will remove the vscsi mapping "vtdname"
* ```createmapping(device,vadapter,options = {})``` : Will create a mapping for "device" on "vadapter".
Options : 
-- ```:vtdname``` => the VTD name
-- ```:force``` => (Bool).


## Step by step lpar creation :

Create the hmc object : 

```ruby 
myhmc = PowerVMTools::HMC.new('192.168.1.10',{ :user => 'hscroot',  :passwd => 'abc123'})
```
Once the HMC is created, we can create the Frame Object :
```ruby
myframe = PowerVMTools::Frame.new('Frame1',myhmc)
```
Creating a frame object will populate the VIO Servers on this frame.
Let's create a Lpar object without Frame, and putting the settings together : 

```ruby
mylpar = PowerVMTools::Lpar.new('Lpar1')
mylpar = PowerVMTools::Lpar.new('Lpar1',{:frame => myframe })
options = { :mem => { :max => 16384,
		      :min => 1024,
		      :des => 4096 },
            :cpu => { :desec => 0.4,
	              :minec => 0.1,
	              :maxec => 4,
	              :desvp => 4,
	              :minvp => 1,
	              :maxvp => 8 },
            :ame => 1,
            :procmode => "shared",
            :sharing_mode => "uncap",
            :uncap_weight => "128",
            :max_virtual_slots => "64",
            :profile_name => "default",
            :virtual_eth_adapters => "2/0/19//0/0/ETHERNET0",
            :virtual_scsi_adapters => "10/client/1/vios1/20/0,11/client/2/vios2/20/0",
            :virtual_fc_adapters => "20/client/1/vios1/21//0,21/client/2/vios2/21//0"}
mylpar.setsettings(options)
mylpar.create({:test => false })
```
This Lpar is now created on the specfied frame.
Let's map some vscsi devices : 

```ruby
# get vios vadapter names : 
vadapter_names = mylpar.getvioadaptersnames
# this produces : 
# {vioid => [[adapt_id,adapt_name]]} : 
# {1=>[[10, "vhost0"], [11, "vhost1"], [15, "vfchost0"]],
#  2=>[[10, "vhost0"], [11, "vhost1"], [15, "vfchost0"]]}
# to get VIO id 1 first adapter name : 
#   vadapter_names[1][0][1]
# to get VIO id 2 second Adapter name : 
#   vadapter_names[1][1][1]

myframe.vioservers[0].createmapping("hdisk51",vadapter_names[1][0][1],{:vtdname => 'vdisk1', :force => true})
myframe.vioservers[1].createmapping("hdisk51",vadapter_names[2][0][1],{:vtdname => 'vdisk1', :force => true})
```
For the example, let's create some vfc mappings : 
```ruby 
## let's lookup the vfc device name on the vadapter_names hash.
vio1vfcname = vadapter_names[1].map{ |x| x.grep(/vfchost/).join}.delete_if { |x| x == ""}[0]
vio2vfcname = vadapter_names[2].map{ |x| x.grep(/vfchost/).join}.delete_if { |x| x == ""}[0]
myframe.vioservers[0].mkfcmap(vio1vfcname,"fcs0")
myframe.vioservers[1].mkfcmap(vio2vfcname,"fcs1")
```

Let's start the machine with ```lpar_netboot``` : 

```ruby
mylpar.net_boot({:ip => "192.168.10.15", :netmask => "255.255.255.0", :gateway => "192.168.10.1", :server => "192.168.11.3"})
```

Let's put it all together : 

```ruby 
require 'powervmtools'

myhmc = PowerVMTools::HMC.new('192.168.1.10',{ :user => 'hscroot',  :passwd => 'abc123'})
myframe = PowerVMTools::Frame.new('Frame1',myhmc)
mylpar = PowerVMTools::Lpar.new('Lpar1')
mylpar = PowerVMTools::Lpar.new('Lpar1',{:frame => myframe })
options = { :mem => { :max => 16384,
		      :min => 1024,
		      :des => 4096 },
            :cpu => { :desec => 0.4,
	              :minec => 0.1,
	              :maxec => 4,
	              :desvp => 4,
	              :minvp => 1,
	              :maxvp => 8 },
            :ame => 1,
            :procmode => "shared",
            :sharing_mode => "uncap",
            :uncap_weight => "128",
            :max_virtual_slots => "64",
            :profile_name => "default",
            :virtual_eth_adapters => "2/0/19//0/0/ETHERNET0",
            :virtual_scsi_adapters => "10/client/1/vios1/20/0,11/client/2/vios2/20/0",
            :virtual_fc_adapters => "20/client/1/vios1/21//0,21/client/2/vios2/21//0"}
mylpar.setsettings(options)
mylpar.create({:test => false })
# get vios vadapter names : 
vadapter_names = mylpar.getvioadaptersnames
# this produces : 
# {vioid => [[adapt_id,adapt_name]]} : 
# {1=>[[10, "vhost0"], [11, "vhost1"], [15, "vfchost0"]],
#  2=>[[10, "vhost0"], [11, "vhost1"], [15, "vfchost0"]]}
# to get VIO id 1 first adapter name : 
#   vadapter_names[1][0][1]
# to get VIO id 2 second Adapter name : 
#   vadapter_names[1][1][1]

myframe.vioservers[0].createmapping("hdisk51",vadapter_names[1][0][1],{:vtdname => 'vdisk1', :force => true})
myframe.vioservers[1].createmapping("hdisk51",vadapter_names[2][0][1],{:vtdname => 'vdisk1', :force => true})
## let's lookup the vfc device name on the vadapter_names hash.
vio1vfcname = vadapter_names[1].map{ |x| x.grep(/vfchost/).join}.delete_if { |x| x == ""}[0]
vio2vfcname = vadapter_names[2].map{ |x| x.grep(/vfchost/).join}.delete_if { |x| x == ""}[0]
myframe.vioservers[0].mkfcmap(vio1vfcname,"fcs0")
myframe.vioservers[1].mkfcmap(vio2vfcname,"fcs1")
mylpar.net_boot({:ip => "192.168.10.15", :netmask => "255.255.255.0", :gateway => "192.168.10.1", :server => "192.168.11.3"})
```

