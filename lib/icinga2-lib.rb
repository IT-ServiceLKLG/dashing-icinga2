
#/******************************************************************************
# * Icinga 2 Dashing Lib                                                       *
# * Copyright (C) 2016-2017 LKLG IT-Service (https://it-service.lklg.net)      *
# *                                                                            *
# * This program is free software; you can redistribute it and/or              *
# * modify it under the terms of the GNU General Public License                *
# * as published by the Free Software Foundation; either version 2             *
# * of the License, or (at your option) any later version.                     *
# *                                                                            *
# * This program is distributed in the hope that it will be useful,            *
# * but WITHOUT ANY WARRANTY; without even the implied warranty of             *
# * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
# * GNU General Public License for more details.                               *
# *                                                                            *
# * You should have received a copy of the GNU General Public License          *
# * along with this program; if not, write to the Free Software Foundation     *
# * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.             *
# ******************************************************************************/

require 'rest-client'
require 'xmlsimple'

$node_name = Socket.gethostbyname(Socket.gethostname).first
if defined? settings.icinga2_api_nodename
  node_name = settings.icinga2_api_nodename
end
$api_url_base = "https://<<icinga_host>>:5665"
if defined? settings.icinga2_api_url
  api_url_base = settings.icinga2_api_url
end
$api_username = "<<icinga_api_user>>"
if defined? settings.icinga2_api_username
  api_username = settings.icinga2_api_username
end
$api_password = "<<icinga_api_pass>>"
if defined? settings.icinga2_api_password
  api_password = settings.icinga2_api_password
end

$cachedir = "/tmp"

# prepare the rest client ssl stuff
def prepare_rest_client(api_url)
  # check whether pki files are there, otherwise use basic auth
  if File.file?("pki/" + $node_name + ".crt")
    #puts "PKI found, using client certificates for connection to Icinga 2 API"
    cert_file = File.read("pki/" + $node_name + ".crt")
    key_file = File.read("pki/" + $node_name + ".key")
    ca_file = File.read("pki/ca.crt")

    cert = OpenSSL::X509::Certificate.new(cert_file)
    key = OpenSSL::PKey::RSA.new(key_file)

    options = {:ssl_client_cert => cert, :ssl_client_key => key, :ssl_ca_file => ca_file, :verify_ssl => OpenSSL::SSL::VERIFY_NONE}
  else
    #puts "PKI not found, using basic auth for connection to Icinga 2 API"

    options = { :user => $api_username, :password => $api_password, :verify_ssl => OpenSSL::SSL::VERIFY_NONE }
  end

  res = RestClient::Resource.new(URI.encode(api_url), options)
  return res
end

#returns the icinga2 status
def get_stats()
  api_url = $api_url_base + "/v1/status/CIB"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
  res = rest_client.get(headers)

  return JSON.parse(res.body)
end

def get_app()
  api_url = $api_url_base + "/v1/status/IcingaApplication"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
  res = rest_client.get(headers)

  return JSON.parse(res.body)
end

#returns all known hosts
def get_hosts()
  api_url = $api_url_base + "/v1/objects/hosts"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
  res = rest_client.get(headers)
  
  return JSON.parse(res.body)
end

#returns icinga check results of a given host
def get_host(name)
  api_url = $api_url_base + "/v1/objects/hosts?host=" + name
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
  res = rest_client.get(headers)

  return parse_icinga_check_data(JSON.parse(res.body))
end

#returns the check results of a complete host group
def get_host_group(name)
  api_url = $api_url_base + "/v1/objects/hosts?filter=\"" + name + "\" in host.groups"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
  res = rest_client.get(headers)

  return parse_icinga_check_data(JSON.parse(res.body))
end

#returns the overall status incl. services of a hostgroup
def get_host_group_status(name)
  group = get_host_group(name)
  status = "normal"
  group.each do |v|
    #get all services from the host
    services = get_host_services(v["name"])
    #get the status_id of the "service group"
    s = get_group_status_id(services)
    #get the dashing status and overwrite it with "higher" status
    status = get_status(s,status)
  end
  return status
end

#returns the overall icinga status id incl. services of a hostgroup
def get_host_group_status_id(name)
  status = get_host_group_status(name)
  state = get_status_id(status)
  return state
end

#returns all known services
def get_services()
  api_url = $api_url_base + "/v1/objects/services"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
  res = rest_client.get(headers)

  return JSON.parse(res.body)
end

#returns check result of a given service
def get_service(host,service,datatype=0)
  api_url = $api_url_base + "/v1/objects/services/?service=" + host + "!" + service
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
  res = rest_client.get(headers)
  
  data = parse_icinga_check_data(JSON.parse(res.body))
  case datatype
    when 1 #return icinga status
      return data['state'] 
    when 2 #return dashing status
      return get_status(data['state'])
    else
      return data #return full data
  end
end

#returns check results for all services from a given hosts
def get_host_services(host)
  api_url = $api_url_base + "/v1/objects/services/?filter=match(\"" + host + "\",service.host_name)"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
  res = rest_client.get(headers)

  #build a shorter array for return
  return parse_icinga_check_data(JSON.parse(res.body))
end

#returns the overall status of a host
def get_host_status(host)
  #get all services from the host
  services = get_host_services(host)
  #get the status_id of the "service group"
  status = get_group_status(services)
  return status
end

#returns the overall host status id
def get_host_status_id(host)
  status = get_host_status(host)
  state = get_status_id(status)
  return state
end

#returns the number of problems a given array with check results
def count_problems(object)
  problems = 0

  object.each do |item|
    item.each do |k, d|
      if (k != "attrs")
        next
      end

      #TODO remove once 2.5 has been released
      if not d.has_key?("downtime_depth")
        d["downtime_depth"] = 0
      end

      if (d["state"] != 0 && d["downtime_depth"] == 0 && d["acknowledgement"] == 0)
        problems = problems + 1
        #puts "Key: " + key.to_s + " State: " + d["state"].to_s
      end
    end
  end

  return problems
end

#make the check result hash/array shorter
def parse_icinga_check_data(data)
  length = data["results"].length

  res_multiple = []
  res_single = {}

  #loop through the data and get some values
  data["results"].each do |v|
    r = {}
    #reset values
    ack = 0
    perfdata = ""
    state = 0
    output = ""
    time = 0
    name = ""
    type = ""
    #check if last_check_result values exits
    if (v["attrs"]["last_check_result"])
      output &&= v["attrs"]["last_check_result"]["output"]
      perfdata &&= v["attrs"]["last_check_result"]["performance_data"]
      state &&= v["attrs"]["last_check_result"]["state"].to_i
    end
    time &&= v["attrs"]["last_check"]
    name &&= v["attrs"]["name"]
    type &&= v["attrs"]["type"]
    ack &&= v["attrs"]["acknowledgement"].to_i
    #set special state if problem was acknowledged
    if ack != 0
      state = 9
    end
    r['output'] = output
    r['perfdata'] = perfdata
    r['state'] = state
    r['time'] = time
    r['name'] = name
    r['type'] = type

    res_single = r
    res_multiple.push(r)
  end
  
  #don't return array if there is only one item
  if length == 1
    return res_single
  else
    return res_multiple
  end
end

#returns the perfdata as an array
def parse_icinga_perfdata(perfdata)
  res = perfdata[perfdata.index("=")+1..perfdata.length]
  res = res.split(";")
  #0=value,1=warn,2=crit,3=min,4=max
  return res
end

#gets the service and returns a specific perfdata
def get_icinga_perfdata(host,service,id=0,datatype=0,unit="")
  s = get_service(host,service)
  data = parse_icinga_perfdata(s['perfdata'][id])
  case datatype
    when 1
      return data[0].to_f #return perfdata value
    when 2
      return [s['state'],data[0].to_s + unit] #return check_state and perfdata value
    else
      return data #return perfdata array
  end
end

#returns a list for dashing
def create_item_list(items)
  list = []
  items.each do |k,v|
    value = ""
    #check if perfdata exist
    if v.is_a?(Array)
      value = v[1].to_s
      switch = v[0]
    else
      switch = v
    end
      case switch
        when 0
          icon = "<i class='icon-ok'>"
        when 1
          icon = "<i class='icon-warning-sign'>"
        when 2
          icon = "<i class='icon-remove'>"
        when 9
          icon = "<i class='icon-cog'></i>"
        else
          icon = "<i class='icon-question-sign'>"
      end
    value += icon
    list.push({:label=>k, :value=>value})
  end
  return list
end

#returns the status of a list
def get_list_status(items)
  status = "normal"
  items.each do |k,v|
    if v.is_a?(Array)
      s = v[0]
    else
      s = v
    end
    #use the status function to overwrite status if it is not "normal"
    status = get_status(s,status)
    #if status == danger we can exit the loop
    if (status == "danger")
      break
    end
  end
  return status
end

#converts the "icinga check status" to the "dashing status"
def get_status(state,oldstate="normal")
  status = oldstate
  case state
    when 0
      #only set if oldstate is also normal
      if (oldstate == "normal")
        status = "normal"
      end
    when 1
      #only set if old status is normal, unknown or acknowledge
      if (oldstate == "normal" or oldstate == "unknown" or oldstate == "acknowledge")
        status = "warning"
      end
    when 2
      #we can exit
      status = "danger"
      #break
    when 9
      #only if old status is normal
      if (oldstate == "normal")
        status = "acknowledge"
      end
    else
      #only set if old status is normal or acknowledge
      if (oldstate == "normal" or oldstate == "acknowledge")
        status = "unknown"
      end
    end
  return status
end

#converts dashing status to icinga state id
def get_status_id(status)
  case status
    when "normal"
      state = 0
    when "warning"
      state = 1
    when "danger"
      state = 2
    when "acknowledge"
      state = 9
    else
      state = 3
  end
  return state
end


#if we need to generate the state for a specific perfdata instead of using the state of the service
def get_perfdata_status(perfdata)
  value = perfdata[0].to_f
  warn = perfdata[1].to_f
  crit = perfdata[2].to_f
  #puts "value: #{value}, warn: #{warn}, crit: #{crit}"
  if value >= crit
    status = "danger"
  elsif value >= warn
    status = "warning"
  else
    status = "normal"
  end
  return status
end

#returns the status id for perfdata
def get_perfdata_status_id(perfdata)
  status = get_perfdata_status(perfdata)
  state = get_status_id(status)
  return state
end

#returns the status of a group (host or service)
def get_group_status(group)
  status = "normal"

  if group.is_a?(Array)
    group.each do |v|
      s = v['state']
      status = get_status(s,status)
      #if status == danger we can exit the loop
      if (status == "danger")
        break
      end
    end
  else #if the host has no services
    s = group['state']
    status = get_status(s,status)
  end
  return status
end

#returns the status_id of a group
def get_group_status_id(group)
  status = get_group_status(group)
  case status
    when "normal"
      state = 0
    when "warning"
      state = 1
    when "danger"
      state = 2
    when "acknowledge"
      state = 9
    else
      state = 3
  end
  return state
end

def set_graph_point(y,service)
  x = Time.now().to_i #timestamp
  file = $cachedir + "/" + service + ".xml"
  xs = XmlSimple.new()
  graph = Hash.new()
  graph["point"] = Array.new()

  #try to load exisiting values from file
  if (File.file?(file) and not File.zero?(file))
    oldgraph = xs.xml_in(file)
    #delete old values (>24hours)
    oldgraph["point"].delete_if {|i| i["x"].to_i < (x - 86400)}
    #add the old points
    graph = oldgraph
  end
  #add the new point
  graph["point"].push({:x=>x, :y=>y.to_f})
  #write file
  File.open(file,'w') do |f|
    f.write xs.xml_out(graph)
  end
end
def get_graph_points(service,seconds)
  file = $cachedir + "/" + service + ".xml"
  t = Time.now().to_i
  t_start = t - seconds
  #only if data exist
  if (File.file?(file) and not File.zero?(file)) 
    f = File.read(file)
    graph = XmlSimple.xml_in(f)

    #select only points that are newer than t_start
    graph["point"].keep_if {|i| i["x"].to_i >= t_start}
    #convert timestamp to x-value
    res = []
    graph["point"].each do |i|
      x = i["x"].to_i - t_start
      y = i["y"].to_f
      res.push({:x=>x, :y=>y})
    end
    return res
  else
    return [0,0]
  end

end
