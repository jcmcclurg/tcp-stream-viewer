require 'rubygems'
require 'sinatra'
require 'thin'

class Transaction
   attr_reader :clientRequest, :clientRequestURI, :serverResponse, :serverResponseHeaders, :serverResponseBody, :serverResponseStatus
   
   def initialize()
     @serverResponse = "";
     @clientRequest  = ""; 
   end
   
   def serverResponse=(response)
      @serverResponse = response
      
      @serverResponseHeaders = getResponseHeaders(response)
      @serverResponseStatus = getResponseStatus(response)
      @serverResponseBody = getResponseBody(response)
      
   end
   
   def clientRequest=(request)
      @clientRequest = request
      @clientRequestURI = getRequestURI(request)
   end

   private

   def getRequestURI(request)
      match = request.match(/\AGET ([^\n\r ]+) .+Host: ([^\n\r]+)/m)
      
      if !match.nil?
         match[2].concat(match[1])
      end
   end

   def getResponseStatus(response)
      match = response.match(/\AHTTP[^\r\n ] ([0-9]+ [^\r\n]+)/m)
      
      if !match.nil?
         match[1]
      end
   end
   
   def getResponseHeaders(response)
      header = Hash.new
      lines = response.split(/\r\n/)
      lines.shift
      lines.each do |line|
         if !line.nil? && line != ""
            match = line.match(/^([^ ]+): (.+)$/)
            header[match[1]] = match[2]
         else
            break
         end
      end
      
      header
   end
   
   def getResponseBody(response)
      response.sub(/\A.+?(\r?\n){2}/m,"")
   end
end

# Use wireshark to do initial parsing of the raw dump file. Our goal is to
# eventually mimic the "Follow Stream" behavior of the wireshark dialog box.
dumpFile = "testing/josiahland.wireshark.tcpdump"
parsedPackets = `tshark -r #{dumpFile} -R "tcp.stream && data" -T fields -e tcp.stream -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e data`
parsedPackets = parsedPackets.split("\n")

# We now have an array of individual packets. Let's separate these packets out
# into arrays of individual $streams. The format of this array will be:
# "clientIP:port serverIP:port" => array of Transaction objects
$streams = Hash.new # The stream array
$streamInfo = Array.new # An array of information about the $streams
transactionMode = Hash.new # A temporary variable to keep track of the
# current stream directions

parsedPackets.each do |parsedPacket|
   parsedPacket = parsedPacket.split("\t")

   streamID = parsedPacket[0]

   # Wireshark displays the packet payload as an ASCII hexadecimal digit. We're
   # going to change this back into a UTF-8 string
   packetBytes = Array.new
   packetData = parsedPacket[5].scan(/.{2}/)
   packetData.each do |chr|
      packetBytes.push(chr.hex)
   end
   packetData = packetBytes.pack("U*")

   # Switch stream directions on GET requests and HTTP responses
   if !packetData.match(/\AGET [^\r\n ]+/).nil?
      if transactionMode[streamID] == "clientRequest"
         abort("Got confused by two GET requests in a row:\n\n#{$streams[streamID].last.clientRequest}\n###########\n#{packetData}")
      end

      transactionMode[streamID] = "clientRequest"
      
      if !$streams.has_key?(streamID)
         $streams[streamID] = Array.new
         $streamInfo.push({"client"=>"#{parsedPacket[1]}:#{parsedPacket[2]}","server"=>"#{parsedPacket[3]}:#{parsedPacket[4]}","streamID"=>streamID})
      end
      $streams[streamID].push(Transaction.new)
      
#      puts "Starting new clientRequest on #{streamID}"
   elsif transactionMode[streamID] == "clientRequest" && !packetData.match(/\AHTTP/).nil?
      transactionMode[streamID] = "serverResponse"
#      puts "Switching to serverResponse mode on #{streamID}"
   end # Switch stream directions

   if $streams.has_key?(streamID)
      if transactionMode[streamID] == "clientRequest"
        $streams[streamID].last.clientRequest += packetData
#        puts "Writing to clientRequest on #{streamID}"
      else
        $streams[streamID].last.serverResponse += packetData
#        puts "Writing to serverResponse on #{streamID}"
      end
   else
#     puts "Ignoring packet from #{streamID} because it does not begin with a GET request."
   end
   
end# Parse packets into $streams

# This Middleware application serves up the requested captured HTTP response.
class MyMiddleware
   def initialize(app)
      @app = app
   end

   def call(env)
      rack_input = String.new
      
      if env["QUERY_STRING"] == "bubba"
         puts "crayzay web response "
         
         status = $streams["3"][0].serverResponseStatus
         headers = $streams["3"][0].serverResponseHeaders
         body = $streams["3"][0].serverResponseBody
         
         puts headers
         
         [status, headers, body]
      else
         puts "normal web response"
         @app.call(env)
      end      
   end
end

# Start piping everything through the custom Middleware application we've built
# to serve up the captured HTTP responses
use MyMiddleware

get "/" do
# print $streams
   outputStr = String.new
   $streamInfo.each do |sinfo|
      outputStr << "<h1>#{sinfo["client"]} <-- #{sinfo["server"]} (#{sinfo["streamID"]})</h1>\n"
      outputStr << "<ul>\n"

      $streams[sinfo["streamID"]].each do |transaction|
         outputStr << "<li><a href=\"#{transaction.clientRequestURI}\" title=\"#{transaction.clientRequest}\">#{transaction.clientRequestURI}</a></li>\n"
      end

      outputStr << "</ul>\n"
      outputStr << "\n\n"
   end# print $streams

   "<html><header><title>Hi</title></header><body>Hello World! You are a good world.\n<br />\n#{outputStr}</body></html>"
end
