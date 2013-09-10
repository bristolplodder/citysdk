# encoding: utf-8

$LOAD_PATH.unshift File.dirname(__FILE__)
require 'active_support/core_ext'
require 'faraday'
require 'sinatra'
require 'json'

require './services_utils.rb'

configure do | sinatraApp |
  set :environment, :production  
  if defined?(PhusionPassenger)
    PhusionPassenger.on_event(:starting_worker_process) do |forked|
      if forked
        # We're in smart spawning mode.
        CitySDK_Services.memcache_new  
      end
      # Else we're in direct spawning mode. We don't need to do anything.
    end
  end   
end

class CitySDK_Services < Sinatra::Base
  def do_abort(code,message)
    throw(:halt, [code, {'Content-Type' => 'application/json'}, message])
  end

  before do
    
  end
  
  after do
    content_type 'application/json'
  end

  def parse_request_json
    begin  
      return JSON.parse(request.body.read)
    rescue => exception
      self.do_abort(422, {"result"=>"fail", "error"=>"Error parsing JSON", "message"=>exception.message}.to_json)
    end
  end
  
  def httpget(connection, path)
    response = ''
    begin
      response = connection.get do |req|
        req.url path
        req.options[:timeout] = 5
        req.options[:open_timeout] = 2
      end
    rescue Exception => e
      self.do_abort(408, {"result"=>"fail", "error"=>"Error requesting resource.", "message"=>e.message}.to_json)
    end
    return response
  end

  
  
  get '/' do
    { :status => 'success', 
      :url => request.url, 
    }.to_json 
  end
  
  ##############################################################################################################
  ## Helsinki Open311 ##########################################################################################
  ##############################################################################################################
  
  Helsinki311_URL = "https://asiointi.hel.fi"
  Helsinki311_PATH = "/palautews/rest/v1/requests.json?service_request_id="
  post '/311.helsinki' do
    @json = self.parse_request_json
    
    @connection = Faraday.new(:url => Helsinki311_URL, :ssl => {:verify => false, :version => 'SSLv3'}) do |c|
      c.use Faraday::Request::UrlEncoded  # encode request params as "www-form-urlencoded"
      # c.use Faraday::Response::Logger     # log request & response to STDOUT
      c.use Faraday::Adapter::NetHttp     # perform requests with Net::HTTP
    end

    resp = httpget(@connection, Helsinki311_PATH + @json['service_request_id'])
    data = JSON.parse(resp.body)
    
    @json = data[0] if resp.status == 200
    return { :status => 'success', 
      :url => request.url, 
      :data => @json
    }.to_json 
  end
  
  #############################################################################################################
  ## SmartCitizen sensors #####################################################################################
  #############################################################################################################
  
    # curl --data '{"sensorid":"216"}' http://services.citysdk.waag.org/sck
  SCK_KEY = JSON.parse(File.read('/var/www/citysdk/shared/config/sck.json').force_encoding('utf-8'))['key'] 
  SCK_URL = "http://api.smartcitizen.me"
  SCK_PATH = "/v0.0.1/#{SCK_KEY}/"
  post '/sck' do
    @json = self.parse_request_json
    
    @connection = Faraday.new(:url => SCK_URL) do |c|
      c.use Faraday::Request::UrlEncoded  # encode request params as "www-form-urlencoded"
      # c.use Faraday::Response::Logger     # log request & response to STDOUT
      c.use Faraday::Adapter::NetHttp     # perform requests with Net::HTTP
    end
    
    resp = httpget(@connection, SCK_PATH + "#{@json['sensorid']}/posts.json")
    if resp.status == 200
      h = JSON.parse(resp.body)
      @json['update'] = h['device']['posts'][0]['insert_datetime']
      @json['battery'] = h['device']['posts'][0]['bat'].to_s + "%"
      @json['light'] = h['device']['posts'][0]['light'].to_s + "%"
      @json['temperature'] = h['device']['posts'][0]['temp'].to_s + "℃"
      @json['humidity'] = h['device']['posts'][0]['hum'].to_s + "%"
      @json['noise'] = h['device']['posts'][0]['noise'].to_s + "dB"
      @json['co'] = h['device']['posts'][0]['co'].to_s + "㏀"
      @json['no2'] = h['device']['posts'][0]['no2'].to_s + "㏀"
    end
    
    return { 
      :status => 'success', 
      :url => request.url, 
      :data => @json
    }.to_json 
  end
  
  ##############################################################################################################
  ## Amsterdam Open311 #########################################################################################
  ##############################################################################################################  
    
  Amsterdam311_URL = "http://open311.dataplatform.nl"
  Amsterdam311_PATH = "/opentunnel/open311/v21/requests.xml?jurisdiction_id=0363&api_key=" + JSON.parse(File.read('/var/www/citysdk/shared/config/adam311.json'))['key'] + "&service_request_id="
  post '/311.amsterdam' do
    @json = self.parse_request_json
    
    @connection = Faraday.new(:url => Amsterdam311_URL) do |c|
      c.use Faraday::Request::UrlEncoded  # encode request params as "www-form-urlencoded"
      # c.use Faraday::Response::Logger     # log request & response to STDOUT
      c.use Faraday::Adapter::NetHttp     # perform requests with Net::HTTP
    end

    resp = httpget(@connection, Amsterdam311_PATH + @json['service_request_id'])
    if resp.status == 200
      @json = Hash.from_xml(resp.body)['service_requests']['request']
    end
    
    return { 
      :status => 'success', 
      :url => request.url, 
      :data => @json
    }.to_json 
  end
  
  post '/divv_tf' do
    puts "maar hier wel"
    # dummy; added for consistent implemtation of rt services.
    # values are always retrieved from memcache, so this should never be called.
    @json = self.parse_request_json
    return { :status => 'success', 
      :url => request.url, 
      :data => @json
    }.to_json 
  end
  
  ##############################################################################################################
  ## Buienradar ################################################################################################
  ##############################################################################################################
    
  # http://gps.buienradar.nl/getrr.php?lat=52.3715975723131&lon=4.89971325769402
  BR_Url = "http://gps.buienradar.nl" 
  BR_Getr = "/getrr.php?"
  # curl --data '{"centroid:lat":"52.3715975723131", "centroid:lon":"4.89971325769402"}' http://localhost:3000/rain
  post '/rain' do
    
    @json = self.parse_request_json
    
    lat = @json["centroid:lat"]
    lon = @json["centroid:lon"]
    
    @connection = Faraday.new :url => BR_Url
    response = httpget(@connection,BR_Getr + "lat=#{lat}&lon=#{lon}")
    data = {:centroid => {:lat => lat, :lon => lon}, :rain => {}}
    
    if response.status == 200
      response.body.split(' ').each do |d|
        value, time = d.split('|')
        value = value.to_i
        data[:rain][time] = value
      end
      return { 
        :status => 'success', 
        :url => request.url, 
        :data => data
      }.to_json 
    else
      self.do_abort(response.status, {"result"=>"fail", "error"=>"Error requesting resource", "message"=>exception.message}.to_json)
    end
  end

  ##############################################################################################################
  ## Nederlandse Spoorwegen ####################################################################################
  ##############################################################################################################
  
  
  NS_Key = JSON.parse(File.read('/var/www/citysdk/shared/config/nskey.json')) 
  NS_Url = "https://webservices.ns.nl" 
  NS_AVT = "/ns-api-avt?station="
  NS_Prijzen = "/ns-api-prijzen-v2?"
  NS_Stations = "/ns-api-stations"
  NS_Storingen = "/ns-api-storingen?"
  NS_Planner = "/ns-api-treinplanner?"
  
  NS_CDK_IDS = JSON.parse(File.read('ns/cdk_ids.json').force_encoding('utf-8')) 
  NS_STATION_CODES = JSON.parse(File.read('ns/station_codes.json').force_encoding('utf-8')) 
  NS_LINES = JSON.parse(File.read('ns/lines.json').force_encoding('utf-8')) 
  
  # curl -u tom@waag.org:mGdLkTCCW8419MeZ2LtpEjvuLZzN08agECQY7eZihoCADK8F45cakg https:webservices.ns.nl/ns-api-avt?station=HT
  # curl --data '{"code":"HT", "land":"NL", "type":"knooppuntIntercitystation", "uiccode":"8400319"}' http://services.citysdk.waag.org/ns_avt
  post '/ns_avt' do
    
    @json = self.parse_request_json
    
    if @json['code'] and @json['code'] != ''
      @connection = Faraday.new :url => NS_Url, :ssl => {:verify => false}
      @connection.basic_auth(NS_Key["usr"], NS_Key["key"])

      data = @json
      response = httpget(@connection,NS_AVT + @json['code'])
      if response.status == 200
        h = Hash.from_xml(response.body)
        
        data["VertrekkendeTreinen"] = []
        
        if h['ActueleVertrekTijden'] and h['ActueleVertrekTijden']['VertrekkendeTrein']
        
          h['ActueleVertrekTijden']['VertrekkendeTrein'].each { |vt|
          
            vertrekkende_trein = {
              :type => vt["TreinSoort"].downcase.gsub(/\W+/, '_'),
              :vervoerder => vt["Vervoerder"],
              :ritnummer => vt["RitNummer"].to_i,
              :vertrektijd => vt["VertrekTijd"],
              :route => {},
              :eindbestemming => {
                :naam => vt["EindBestemming"]              
              },
              :spoor => vt["VertrekSpoor"]
            }
          
            vertrekkende_trein[:reistip] = vt["ReisTip"].strip if vt["ReisTip"]
            if vt["Opmerkingen"]
              vertrekkende_trein[:opmerkingen] = vt["Opmerkingen"].values.map { |opmerking| opmerking.strip }
            end
            vertrekkende_trein[:route][:tekst] = vt["RouteTekst"] if vt["RouteTekst"]
                
            # Vertrekvertraging
            if vt["VertrekVertraging"]
              vertrekkende_trein[:vertraging] = {
                :minuten => vt["VertrekVertraging"] =~ /(\d+)/ ? $1.to_i : 0,
                :tekst => vt["VertrekVertragingTekst"]
              }           
            end
                                    
            # Eindbestemming, code & cdk_id:
            code = NS_STATION_CODES[vt['EindBestemming']]
            cdk_id = NS_CDK_IDS[code]
            type = vt["TreinSoort"].downcase.gsub(/\W+/, '_')
          
            vertrekkende_trein[:eindbestemming][:code] = code if code
            vertrekkende_trein[:eindbestemming][:cdk_id] = cdk_id if cdk_id   

            # Route
            line = nil
            if NS_LINES.has_key? type
              NS_LINES[type].each { |l|
                # Two options to check whether l is the correct line
                # 1. l must contain code and @json['code'] with index of code > index @json['code']
                # 2. code must be terminus of l and l must contain @json['code']
              
                if i1 = l.index(@json['code']) and i2 = l.index(code) and i1 < i2 # Option 1
                #if l[-1] == code and l.include? @json['code'] # Option 2
                  line = l
                  break
                end
              }
            end
          
            if line
              vertrekkende_trein[:route][:cdk_id] = "ns.#{type}.#{line[0]}.#{line[-1]}".downcase
              vertrekkende_trein[:route][:stations] = line.map { |code|  NS_CDK_IDS[code]}
            end
          
            data["VertrekkendeTreinen"] << vertrekkende_trein   
          }        
        
        end
        
        return { :status => 'success', 
          :url => request.url, 
          :data => data
        }.to_json 
      else
        self.do_abort(response.status, {"result"=>"fail", "error"=>"Error requesting resource", "message"=>response.body}.to_json)
      end

    else
      return { :status => 'success', 
        :url => request.url, 
        :data => @json
      }.to_json 
    end
      
  end
  
  ##############################################################################################################
  ## Oplaadpalen.nl ############################################################################################
  ##############################################################################################################  
  
  OPLAADPALEN_KEY = JSON.parse(File.read('/var/www/citysdk/shared/config/oplaadpalen_key.json'))["key"]
  OPLAADPALEN_HOST = "http://oplaadpalen.nl"
  OPLAADPALEN_PATH = "/api/availability/#{OPLAADPALEN_KEY}/json"

  post '/oplaadpalen' do
    @json = self.parse_request_json
          
    if @json["realtimestatus"] == "true"
      id = @json["id"]
            
      # TODO: naming convention!
      key = "oplaadpalen!!!#{id}"      
      data = CitySDK_Services.memcache_get(key)
      if data
        @json["availability"] = data
      else
        # Download availability data from oplaadpunten.nl
        @connection = Faraday.new OPLAADPALEN_HOST    
        response = httpget(@connection, OPLAADPALEN_PATH)
        if response.status == 200
          availability = JSON.parse response.body          
          availability.each { |data|
            _id = data["id"]
            data.delete("id")
            
            # Convert strings to integers:
            data = Hash[data.map{|k,str| [k, str.to_i] } ]
            
            if _id == id
              @json["availability"] = data
            end          
            key = "oplaadpalen!!!#{_id}" 
            # TODO: get timeout from layer data
            CitySDK_Services.memcache_set(key, data, 5 * 60 )
          }        
        end
      end      
    end
    
    @json["cards"] = JSON.parse @json["cards"]
    @json["facilities"] = JSON.parse @json["facilities"]
    
    @json["price"] = @json["price"].to_f
    @json["nroutlets"] = @json["nroutlets"].to_i
    @json["realtimestatus"] = (@json["realtimestatus"] == "true")
    @json["id"] = @json["id"].to_i
        
    @json.select! { |k,v| v != '' } 
      
    return { :status => 'success', 
      :url => request.url, 
      :data => @json
    }.to_json 
  end 
  
  ##############################################################################################################
  ## Arts Holland ##############################################################################################
  ############################################################################################################## 

  AH_Key = '91f8cb2755d2683eb442b3837dbe6274' 
  AH_Query = File.open('artsholland.sparql','r').read
  AH_Url = "http://api.artsholland.com" 

  post '/artsholland' do
    
    @json = self.parse_request_json
    
    # @json = {
    #   'title' => 'Rijksmuseum',
    #   'uri' => 'http://data.artsholland.com/venue/1998-l-001-0000187'
    # }
    
    if @json['uri'] and @json['uri'] != ''
      
      start_date = DateTime.now.strftime()
      end_date = (DateTime.now + 2.week).strftime()      
      
      ahPostData = {
        :output => :json,
        :query => AH_Query % [@json['uri'], start_date, end_date]
      }

      @connection = Faraday.new :url => AH_Url
      response = @connection.post do |req|
        req.url '/sparql'
        req.headers = {
         'Content-Type' => 'application/x-www-form-urlencoded',
         'Accept' => 'application/sparql-results+json'
        }
        req.params['api_key'] = AH_Key
        req.body = ahPostData
      end

      events = []
      if response.status == 200 
         results = JSON.parse(response.body)
         
         results["results"]["bindings"].each { |event|
           events << {
             :title => event["title"]["value"],
             :time => event["time"]["value"],
             :event_uri => event["e"]["value"],
             :production_uri => event["p"]["value"],
           }
         }
                  
         return { :status => 'success', 
           :url => request.url, 
           :data => @json.merge({
             :events => events
           })           
         }.to_json         

      else
        self.do_abort(response.status, {"result"=>"fail", "error"=>"Error requesting resource", "message"=>response.body}.to_json)
      end

    else
      return { :status => 'success', 
        :url => request.url, 
        :data => @json
      }.to_json 
    end
    
  end

end
