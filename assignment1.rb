class Mobile_Switching_Center
  attr_accessor :base_station_controllers

  def initialize()
    @base_station_controllers = []
  end

  def do_handoff(new_base_station_id,mobile_handset)
    puts "MSC: Doing Handoff"
    base_stations = self.base_station_controllers[1].base_stations.merge(self.base_station_controllers[2].base_stations)
    new_base_station = base_stations[new_base_station_id]
    new_base_station.base_station_controller.do_handoff(new_base_station,mobile_handset)
  end

  def send_handoff_ack(new_base_station,mobile_handset)
    puts "MSC: Sending Handoff Command to old BSC"
    mobile_handset.cell.base_station.base_station_controller.send_handoff_command(new_base_station,mobile_handset)
  end

  def indicate_handoff_completion(old_base_station,mobile_handset)
    puts "MSC: Handoff Completion Indicated. Indicating same to Old BSC"
    old_base_station.base_station_controller.indicate_handoff_completion_to_old_bs(old_base_station,mobile_handset)
  end

  def indicate_data_flushed
    puts "MSC: Handoff performed successfully."
  end
end
class Base_Station_Controller
  attr_accessor :base_stations, :mobile_switching_center, :id

  def initialize(id)
    @id = id
    @base_stations = []
    @mobile_switching_center = nil
  end

  def request_handoff(new_base_station_id,mobile_handset)
    puts "Old BSC: Handoff Requested"
    self.mobile_switching_center.do_handoff(new_base_station_id,mobile_handset)
  end

  def do_handoff(new_base_station,mobile_handset)
    puts "New BSC: Doing Handoff"
    new_base_station.activate_handoff(mobile_handset)
  end

  def indicate_handoff_activation(new_base_station,mobile_handset)
    puts "New BSC: Indicated Handoff Activation by New BS. Sending Handoff Ack to MSC"
    self.mobile_switching_center.send_handoff_ack(new_base_station,mobile_handset)
  end

  def send_handoff_command(new_base_station,mobile_handset)
    puts "Old BSC: Sending Handoff Ack to Old BS"
    mobile_handset.cell.base_station.receive_handoff_ack(new_base_station,mobile_handset)
  end

  def indicate_handoff_completion(old_base_station,mobile_handset)
    puts "New BSC: Handoff Completion Indicated. Conveying it to MSC."
    self.mobile_switching_center.indicate_handoff_completion(old_base_station,mobile_handset)
  end

  def indicate_handoff_completion_to_old_bs(old_base_station,mobile_handset)
    puts "Old BSC: Handoff Completion Indicated. Telling Old BS to flush data"
    old_base_station.flush_data(mobile_handset)
  end

  def indicate_data_flushed
    puts "Old BSC: Data Flushed. Indicating same to MSC"
    self.mobile_switching_center.indicate_data_flushed
  end
end
class Base_Station
  attr_accessor :id, :cells, :base_station_controller, :agch_channel, :sacch_channel
  def initialize(id)
    @id = id
    @cells = []
    @agch_channel = Channel.new("AGCH",id.to_s+"agch")
    @sacch_channel = Channel.new("SACCH",id.to_s+"sacch")
    @base_station_controller = nil
    @agch_channel.base_station = self
    @sacch_channel.base_station = self
  end

  def receive_measurements(measurements,mobile_handset)
    if (measurements[(self.id)] < -100)
      puts "Old BS: Signal Low"
      new_base_station_id = measurements.max_by {|k,v| v}[0]
      initiate_handoff(new_base_station_id,mobile_handset)
    else
      puts "Old BS: Signal more than -100 dBm. No Handoff needed"
    end
  end

  def initiate_handoff(new_base_station_id,mobile_handset)
    puts "Old BS: Initiating Handoff"
    self.base_station_controller.request_handoff(new_base_station_id,mobile_handset)
  end

  def activate_handoff(mobile_handset)
    puts "New BS: Checking if Handoff is possible"
    if Random.rand(1..100) > 25
      puts "New BS: Handoff Possible. Indicating Handoff Activation."
      self.base_station_controller.indicate_handoff_activation(self,mobile_handset)
    else
      puts "New BS: Handoff not possible. Call will be dropped."
      mobile_handset.tch_channel = nil
      return
    end
  end

  def receive_handoff_ack(new_base_station,mobile_handset)
    puts "Old BS: Opening new AGCH Channel to send Link Active Message to MH"
    self.agch_channel.send_message({"link_status"=>"active","new_base_station"=>new_base_station},mobile_handset)
  end

  def request_link_activation(mobile_handset)
    puts "New BS: Link Activation requested by MH. Completing Link Establishment"
    old_base_station = mobile_handset.cell.base_station
    mobile_handset.complete_link_establishment(self)   
    puts "New BS: Link Establishment Complete. Indicating Handoff Completion" 
    self.base_station_controller.indicate_handoff_completion(old_base_station,mobile_handset)
  end

  def flush_data(mobile_handset)
    puts "Old BS: Flushing Old Data"
    self.cells.values.each do |cell|
      cell.channels.values.each do |channel|
        if channel.mobile_handset == mobile_handset
          channel.mobile_handset = nil
        end
      end
    end
    self.base_station_controller.indicate_data_flushed
  end
end
class Cell
  attr_accessor :channels, :base_station, :id
  def initialize(id)
    @id = id
    @channels = []
    @base_station = nil
  end
end
class Channel
  attr_accessor :type, :cell, :base_station, :mobile_handset, :id

  def initialize(type,id)
    @type = type
    @id = id
    @cell = nil
    @base_station = nil
    @mobile_handset = nil
  end

  def send_message(content,mobile_handset)
    case self.type
    when "TCH"

    when "SACCH"
      puts "SACCH: Sending Measurements"
      self.base_station.receive_measurements(content,mobile_handset)
    when "AGCH" 
      puts "AGCH: Sending Link Active Message"
      mobile_handset.receive_link_status(content)
    end
  end
end
class Mobile_Handset
  attr_accessor :cell, :tch_channel

  def initialize()
    @cell = nil
    @tch_channel = nil
  end

  def get_measurements(base_stations)
    puts "MH: Getting Measurements"
    measurements = Hash.new    
    top_measurements = Hash.new
    base_stations.each do |id, base_station|
      measurements[id] = -1 * Random.rand(60..120)
    end
    i = 1
    measurements.sort_by {|k,v| v}.reverse.each do |key,value|
      if i <= 6
        top_measurements[key] = value
      end
      i+=1
    end
    unless top_measurements.has_key?(self.cell.base_station)
      top_measurements[self.cell.base_station.id] = measurements[self.cell.base_station.id]
    end
    puts "MH: Returning Top Measurements"
    puts top_measurements.inspect
    return top_measurements
  end

  def receive_link_status(content)
    if content["link_status"] == "active"
      puts "MH: Link is active. Request Link Activation from new BS"
      content["new_base_station"].request_link_activation(self)
    end
  end

  def current_base_station
    return self.cell.base_station
  end

  def complete_link_establishment(new_base_station)
    puts "MH: Completing Link Establishment"
    self.cell = new_base_station.cells.values.sample(1).first
    self.tch_channel = self.cell.channels.values.sample(1).first
    self.tch_channel.mobile_handset = self
  end
end

mobile_switching_center = Mobile_Switching_Center.new
base_station_controllers = Hash.new
base_stations = Hash.new
cells = Hash.new
channels = Hash.new

%#
Mobile Handoff Simulation
Author: Abhiroop Bhatnagar(abhiroop@iitk.ac.in)
#
# Set up MS <-> BSC relations
for i in 1..2
  base_station_controllers[i] = Base_Station_Controller.new(i)
  base_station_controllers[i].mobile_switching_center = mobile_switching_center
end
mobile_switching_center.base_station_controllers = base_station_controllers
# Set up BSC <-> BS relations
for i in 1..16
  base_stations[i] = Base_Station.new(i)
  base_station_controller_id = ((i-1) / 8) + 1 
  base_stations[i].base_station_controller = base_station_controllers[base_station_controller_id]
end
base_station_controllers.each do |id,base_station_controller|
  base_station_controller.base_stations = base_stations.select{|k,v| k <= id*8 && k > (id-1)*8 }
end
# Set up BS <-> Cell relations
for i in 1..112
  cells[i] = Cell.new(i)
  base_station_id = ((i-1)/7)+1
  cells[i].base_station = base_stations[base_station_id]
end
base_stations.each do |id,base_station|
  base_station.cells = cells.select{|k,v| k <= id*7 && k > (id-1)*7 }
end
# Set up Cell <-> Channel relations
for i in 1..1568
  channels[i] = Channel.new("TCH",i)
  cell_id = ((i-1)/14)+1
  channels[i].cell = cells[cell_id]
end
cells.each do |id,cell|
  cell.channels = channels.select{|k,v| k <= id*14 && k > (id-1)*14 }
end
puts "Assignment 1: Mobile Handoff Simulation"
puts "Mobile Computing"
puts "Abhiroop Bhatnagar(10327015)"
puts "------------------------------------------"
puts "Structure:"
puts "There are two BSCs under a central MSC."
puts "Each BSC handles 8 BS."
puts "Each BS has 7 cells in it."
puts "Signal strength is set to be a random value between -60 dBm and -120 dBm"
puts "Handoff will be initiated when signal strength drops below -100dBm"
puts "The probability of channel not available at new BS is set to be at 25%."
puts "For simulation purposes, MH sends top 6 signal strength measurements to BS every 2 sec."
puts "Press Enter to begin simulation."
gets
#Initialize the location of Mobile Handset
mobile_handset = Mobile_Handset.new
mobile_handset.cell = cells[1]

#Select TCH Channel at random for initialization
mobile_handset.tch_channel = mobile_handset.cell.channels.values.sample(1).first
mobile_handset.tch_channel.mobile_handset = mobile_handset
puts "Current State ->"
puts "----------------------------------------------------------------------------------------"
puts "| Channel       :      #{mobile_handset.tch_channel.id}                                "
puts "| Cell          :      #{mobile_handset.cell.id}                                       "
puts "| BS            :      #{mobile_handset.cell.base_station.id}                          "
puts "| BSC           :      #{mobile_handset.cell.base_station.base_station_controller.id}  "
puts "----------------------------------------------------------------------------------------"
loop do
  #Send measurements through SACCH
  puts "Preparing to send measurements through SACCH Channel"
  measurements = mobile_handset.get_measurements(base_stations)
  mobile_handset.cell.base_station.sacch_channel.send_message(measurements,mobile_handset)
  if mobile_handset.tch_channel.nil?
    puts "Call dropped"
    break
  else
    puts "Current State ->"
    puts "----------------------------------------------------------------------------------------"
    puts "| Channel       :      #{mobile_handset.tch_channel.id}                                "
    puts "| Cell          :      #{mobile_handset.cell.id}                                       "
    puts "| BS            :      #{mobile_handset.cell.base_station.id}                          "
    puts "| BSC           :      #{mobile_handset.cell.base_station.base_station_controller.id}  "
    puts "----------------------------------------------------------------------------------------"
    sleep 2
  end
end

